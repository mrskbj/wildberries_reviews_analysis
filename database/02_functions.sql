-- --- ОСНОВНЫЕ ФУНКЦИИ --- 

-- --- Функция 1: Предобработка текста ---
-- Используем PL/pgSQL для простых и быстрых операций с текстом.
CREATE OR REPLACE FUNCTION preprocess_text(p_text TEXT)
RETURNS TEXT AS $$
BEGIN
    -- Приводим к нижнему регистру и удаляем лишние символы, оставляя только буквы, цифры и пробелы
    RETURN regexp_replace(lower(p_text), '[^а-яa-z0-9\s]', '', 'g');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Проверяем работу функции предобработки
SELECT preprocess_text('Это Отличный Товар!!! Просто супер, рекомендую 100%');
-- Ожидаемый результат: 'это отличный товар просто супер рекомендую 100'


-- --- Функция 2: Анализ тональности ---
-- Используем plpython3u для доступа к библиотеке transformers.
CREATE OR REPLACE FUNCTION analyze_sentiment(p_text TEXT)
RETURNS TABLE(score NUMERIC(10, 8), label TEXT) AS $$
    # Кэшируем модель в глобальном словаре GD, чтобы не загружать ее при каждом вызове
    if 'sentiment_model' not in GD:
        from transformers import pipeline
        # Используем модель для русского языка
        GD['sentiment_model'] = pipeline(
            'sentiment-analysis',
            model='blanchefort/rubert-base-cased-sentiment'
        )

    # Получаем результат от модели
    model = GD['sentiment_model']
    # Обрезаем текст до 512 токенов, как того требует модель
    result = model(p_text[:512])[0]
    model_label = result['label']
    model_score = result['score']

    # Конвертируем результат в нашу систему: score от -1 до 1 и метки 'positive', 'negative', 'neutral'
    final_score = 0.0
    final_label = 'neutral'

    if model_label == 'POSITIVE':
        final_score = model_score
        final_label = 'positive'
    elif model_label == 'NEGATIVE':
        final_score = -model_score # Делаем оценку отрицательной
        final_label = 'negative'
    else: # NEUTRAL
        final_score = 0.5 - abs(model_score - 0.5) # Чем ближе к 0.5, тем ближе к 0
        final_label = 'neutral'

    return [(final_score, final_label)]
$$ LANGUAGE plpython3u;

-- Проверяем работу функции анализа тональности
-- Позитивный отзыв
SELECT * FROM analyze_sentiment('Мне очень понравился этот телефон, камера просто восхитительная!');
-- Негативный отзыв
SELECT * FROM analyze_sentiment('Ужасное качество, товар сломался на второй день.');
-- Нейтральный отзыв
SELECT * FROM analyze_sentiment('Обычная футболка, ничего особенного.');


-- --- Функция 3: Генерация эмбеддингов ---
CREATE OR REPLACE FUNCTION generate_embedding(p_text TEXT)
RETURNS vector(384) AS $$
    if 'embedding_model' not in GD:
        from sentence_transformers import SentenceTransformer
        # Используем быструю и качественную мультиязычную модель
        GD['embedding_model'] = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')

    model = GD['embedding_model']
    # Генерируем эмбеддинг
    embedding = model.encode(p_text[:512])
    return embedding.tolist()
$$ LANGUAGE plpython3u;

-- Проверяем работу функции генерации эмбеддингов (убедимся, что функция возвращает вектор правильной размерности)
SELECT vector_dims(generate_embedding('Это текст для проверки генерации эмбеддинга.')) as vector_dimensions;
-- Ожидаемый результат: 384


-- --- Функция 4: Извлечение ключевых фраз ---
CREATE OR REPLACE FUNCTION extract_key_phrases(p_text TEXT, p_phrases_count INT DEFAULT 5)
RETURNS TEXT[] AS $$
DECLARE
    -- Убираем стоп-слова 
    v_stop_words TEXT[] := ARRAY[
		'и', 'в', 'во', 'не', 'что', 'он', 'на', 
		'я', 'с', 'со', 'как', 'а', 'то', 'все', 'она', 'так', 'его', 'но', 
		'да', 'ты', 'к', 'у', 'же', 'вы', 'за', 'бы', 'по', 'только', 'ее', 
		'мне', 'было', 'вот', 'от', 'меня', 'еще', 'о', 'из', 'ему', 'теперь', 
		'когда', 'даже', 'ну', 'вдруг', 'ли', 'если', 'уже'
	];
    v_words TEXT[];
    v_result_phrases TEXT[];
BEGIN
    -- Разделяем предобработанный текст на слова
    SELECT string_to_array(preprocess_text(p_text), ' ') INTO v_words;

    -- Отбираем уникальные слова, которые не являются стоп-словами
    SELECT array_agg(DISTINCT word)
    FROM unnest(v_words) as word
    WHERE word <> ALL(v_stop_words) AND length(word) > 3
    INTO v_result_phrases;

    -- Возвращаем нужное количество фраз, если результат NULL, возвращаем пустой массив
    RETURN COALESCE(v_result_phrases[1:p_phrases_count], ARRAY[]::TEXT[]);
END;
$$ LANGUAGE plpgsql;

-- Проверяем работу функции извлечения ключевых фраз
SELECT extract_key_phrases('Очень быстрая доставка и прекрасное качество материалов, телефон просто летает.');
-- Ожидаемый результат: массив типа {'быстрая', 'доставка', 'прекрасное', 'качество', 'материалов'}


-- --- Основная функция 5: Полная обработка одного отзыва ---
-- Эта функция объединяет все шаги для удобства.
CREATE OR REPLACE FUNCTION process_single_review(p_review_id INT)
RETURNS VOID AS $$
DECLARE
    v_review_text TEXT;
    v_processed_text TEXT;
    v_sentiment RECORD;
    v_embedding vector(384);
    v_phrases TEXT[];
    v_phrase TEXT;
BEGIN
    -- 1. Получаем текст отзыва из таблицы
    SELECT review_text INTO v_review_text FROM reviews WHERE review_id = p_review_id;
    IF NOT FOUND THEN
        RAISE NOTICE 'Отзыв с ID % не найден', p_review_id;
        RETURN;
    END IF;

    -- 2. Предобрабатываем текст
    v_processed_text := preprocess_text(v_review_text);
    UPDATE reviews SET processed_text = v_processed_text WHERE review_id = p_review_id;

    -- 3. Анализируем тональность
    SELECT * INTO v_sentiment FROM analyze_sentiment(v_review_text);
    INSERT INTO sentiment_analysis (review_id, sentiment_score, sentiment_label)
    VALUES (p_review_id, v_sentiment.score, v_sentiment.label)
    ON CONFLICT (review_id) DO UPDATE SET
        sentiment_score = EXCLUDED.sentiment_score,
        sentiment_label = EXCLUDED.sentiment_label,
        processed_at = NOW();

    -- 4. Генерируем эмбеддинг
    v_embedding := generate_embedding(v_processed_text);
    INSERT INTO review_embeddings (review_id, embedding, model_name)
    VALUES (p_review_id, v_embedding, 'paraphrase-multilingual-MiniLM-L12-v2')
    ON CONFLICT (review_id) DO UPDATE SET
        embedding = EXCLUDED.embedding,
        model_name = EXCLUDED.model_name,
        generated_at = NOW();

    -- 5. Извлекаем ключевые фразы
    -- Сначала удаляем старые фразы для этого отзыва
    DELETE FROM key_phrases WHERE review_id = p_review_id;
    -- Извлекаем и вставляем новые
    v_phrases := extract_key_phrases(v_processed_text);
    
	IF array_length(v_phrases, 1) > 0 THEN
        FOREACH v_phrase IN ARRAY v_phrases
        LOOP
            INSERT INTO key_phrases (review_id, phrase) VALUES (p_review_id, v_phrase);
        END LOOP;
    END IF;

    RAISE NOTICE 'Отзыв с ID % успешно обработан.', p_review_id;
END;
$$ LANGUAGE plpgsql;
