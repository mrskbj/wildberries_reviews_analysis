-- --- Придумываем данные для проверки функций ---

-- Добавляем товары
INSERT INTO products (product_name) VALUES
('Смартфон "Galaxy S25"'),
('Беспроводные наушники "AudioDream"'),
('Умные часы "Чебурашка"')
ON CONFLICT (product_name) DO NOTHING;

-- Добавляем пользователей
INSERT INTO users (user_name) VALUES
('Анна Кашкина'),
('Виктор Милонов'),
('Елена Кацкая')
ON CONFLICT (user_name) DO NOTHING;

-- Добавляем отзывы с разной тональностью
INSERT INTO reviews (product_id, user_id, review_text, rating, review_date) VALUES
-- Отзыв 1 (Позитивный)
(1, 1, 'Телефон просто огонь! Камера снимает великолепно, батарея держит два дня. Очень довольна покупкой!', 5, NOW() - INTERVAL '1 day'),
-- Отзыв 2 (Негативный)
(2, 2, 'Полное разочарование. Наушники перестали работать через неделю. Звук плоский, шумоподавление отсутствует. Не рекомендую.', 1, NOW() - INTERVAL '2 days'),
-- Отзыв 3 (Нейтральный)
(3, 3, 'Часы как часы. Функции свои выполняют, но ничего выдающегося. Ремешок стандартный, экран нормальный.', 3, NOW() - INTERVAL '3 days'),
-- Отзыв 4 (Смешанный)
(1, 2, 'В целом телефон неплохой, экран яркий. Но батарея садится очень быстро, ожидал большего за такую цену.', 4, NOW() - INTERVAL '4 days'),
-- Отзыв 5 (Короткий негативный)
(2, 1, 'Сломались. Качество ужасное.', 1, NOW() - INTERVAL '5 days');


-- --- Обрабатываем вставленные отзывы с помощью нашей функции ---

-- Вызываем функцию для каждого добавленного отзыва.
DO $$
DECLARE
    last_review_id INT;
BEGIN
    SELECT max(review_id) INTO last_review_id FROM reviews;
    PERFORM process_single_review(id) FROM generate_series(last_review_id - 4, last_review_id) as id;
END $$;


-- --- Проверяем результаты обработки ---

-- Проверяем тональность
SELECT
    r.review_id,
    left(r.review_text, 40) || '...' as review_text,
    r.rating,
    sa.sentiment_label,
    sa.sentiment_score
FROM reviews r
JOIN sentiment_analysis sa ON r.review_id = sa.review_id
ORDER BY r.review_id;

-- Проверяем эмбеддинги
SELECT review_id, model_name, left(embedding::text, 60) || '...' as embedding_start FROM review_embeddings;

-- Проверяем ключевые фразы
SELECT review_id, array_agg(phrase) as phrases FROM key_phrases GROUP BY review_id ORDER BY review_id;
