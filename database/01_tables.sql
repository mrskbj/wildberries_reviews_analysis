-- Добавляем расширения, если они еще не установлены
CREATE EXTENSION IF NOT EXISTS plpython3u;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- --- Основные таблицы ---

-- Таблица с информацией о товарах
CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    product_name TEXT NOT NULL UNIQUE,
    -- Добавляем поле для хранения среднего рейтинга, которое можно обновлять
    avg_rating NUMERIC(3, 2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица с данными о пользователях
CREATE TABLE IF NOT EXISTS users (
    user_id SERIAL PRIMARY KEY,
    user_name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица с отзывами
CREATE TABLE IF NOT EXISTS reviews (
    review_id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE SET NULL,
    review_text TEXT NOT NULL,
    -- Используем SMALLINT для оценок от 1 до 5
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    -- Добавляем колонку для предобработанного текста для ускорения NLP
    processed_text TEXT,
    review_date TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- --- NLP-таблицы ---

-- Таблица с результатами анализа тональности
CREATE TABLE IF NOT EXISTS sentiment_analysis (
    review_id INTEGER PRIMARY KEY REFERENCES reviews(review_id) ON DELETE CASCADE,
    -- Оценка от -1 (негатив) до 1 (позитив)
    sentiment_score NUMERIC(10, 8) NOT NULL,
    -- Метка: positive, neutral, negative
    sentiment_label TEXT NOT NULL CHECK (sentiment_label IN ('positive', 'neutral', 'negative')),
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Таблица для хранения извлеченных ключевых фраз
CREATE TABLE IF NOT EXISTS key_phrases (
    phrase_id SERIAL PRIMARY KEY,
    review_id INTEGER NOT NULL REFERENCES reviews(review_id) ON DELETE CASCADE,
    phrase TEXT NOT NULL,
    score NUMERIC(10, 8) DEFAULT NULL,
    UNIQUE (review_id, phrase)
);

-- Таблица для хранения векторных представлений (эмбеддингов)
-- Модель 'paraphrase-multilingual-MiniLM-L12-v2' имеет размерность 384
CREATE TABLE IF NOT EXISTS review_embeddings (
    review_id INTEGER PRIMARY KEY REFERENCES reviews(review_id) ON DELETE CASCADE,
    embedding VECTOR(384) NOT NULL,
    model_name TEXT NOT NULL,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- --- Индексы для оптимизации запросов ---

-- Индексы для внешних ключей для ускорения JOIN'ов
CREATE INDEX IF NOT EXISTS idx_reviews_product_id ON reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);

-- Составной индекс для частых фильтраций по рейтингу и дате
CREATE INDEX IF NOT EXISTS idx_reviews_rating_date ON reviews(rating, review_date);

-- Индекс для быстрого поиска по метке тональности
CREATE INDEX IF NOT EXISTS idx_sentiment_analysis_label ON sentiment_analysis(sentiment_label);

-- Индекс для полнотекстового поиска по предобработанному тексту
CREATE INDEX IF NOT EXISTS idx_reviews_processed_text_gin ON reviews USING GIN(processed_text gin_trgm_ops);

-- Индекс для приблизительного поиска ближайших соседей (эмбеддинги)
CREATE INDEX IF NOT EXISTS idx_review_embeddings_ivfflat ON review_embeddings USING ivfflat (embedding vector_l2_ops) WITH (lists = 100);


-- --- Триггеры ---

-- Функция для автоматического обновления временной метки 'updated_at'
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Привязываем триггер к таблицам
DROP TRIGGER IF EXISTS set_timestamp ON products;
CREATE TRIGGER set_timestamp
BEFORE UPDATE ON products
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();

DROP TRIGGER IF EXISTS set_timestamp ON users;
CREATE TRIGGER set_timestamp
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();

DROP TRIGGER IF EXISTS set_timestamp ON reviews;
CREATE TRIGGER set_timestamp
BEFORE UPDATE ON reviews
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();
