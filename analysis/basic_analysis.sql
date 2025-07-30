-- Запросы для базового анализа отзывов с использованием оптимизаций.

-- Перед выполнением запросов нужно почистить кэш через выполнение скрипта оптимизации:
-- REFRESH MATERIALIZED VIEW product_analytics_summary;


-- Топ-5 самых обсуждаемых товаров 
-- Помогает понять, какие товары привлекают больше всего внимания.
SELECT
    product_name,
    total_reviews
FROM product_analytics_summary
ORDER BY total_reviews DESC
LIMIT 5;

-- Топ-5 товаров с самым высоким средним рейтингом 
-- Помогает выявить товары-любимчики покупателей.
SELECT
    product_name,
    avg_rating,
    total_reviews
FROM product_analytics_summary
WHERE total_reviews >= 10 -- Учитываем только товары с достаточным количеством отзывов
ORDER BY avg_rating DESC
LIMIT 5;

-- Топ-5 товаров с наибольшим количеством негативных отзывов 
-- Помогает найти самые проблемные товары.
SELECT
    product_name,
    negative_count,
    total_reviews
FROM product_analytics_summary
ORDER BY negative_count DESC
LIMIT 5;

-- Топ-10 самых частых ключевых фраз в позитивных и негативных отзывах
-- Ключевые фразы в позитивных отзывах:
SELECT
    kp.phrase,
    COUNT(*) as frequency
FROM key_phrases kp
JOIN sentiment_analysis sa ON kp.review_id = sa.review_id
WHERE sa.sentiment_label = 'positive'
GROUP BY kp.phrase
ORDER BY frequency DESC
LIMIT 10;

-- Ключевые фразы в негативных отзывах:
SELECT
    kp.phrase,
    COUNT(*) as frequency
FROM key_phrases kp
JOIN sentiment_analysis sa ON kp.review_id = sa.review_id
WHERE sa.sentiment_label = 'negative'
GROUP BY kp.phrase
ORDER BY frequency DESC
LIMIT 10;

-- Поиск семантически похожих, но не идентичных отзывов (ID = 1)
-- Помогает найти похожие мнения, игнорируя полные дубликаты текста.
WITH target_review AS (
  SELECT embedding FROM review_embeddings WHERE review_id = 1
)
SELECT
    r.review_id,
    r.review_text,
    r.rating,
    1 - (re.embedding <=> (SELECT embedding FROM target_review)) as similarity
FROM reviews r
JOIN review_embeddings re ON r.review_id = re.review_id
WHERE
    r.review_id != 1
    -- Исключаем отзывы с почти идеальной схожестью (т.е. дубликаты)
    AND 1 - (re.embedding <=> (SELECT embedding FROM target_review)) < 0.999
ORDER BY similarity DESC
LIMIT 5;

-- Анализ дубликатов: найти тексты отзывов, которые повторяются более 5 раз
-- Помогает выявить спам, накрутки или шаблонные ответы.
SELECT
    COUNT(*) as duplicate_count,
    review_text,
    -- Показываем ID всех отзывов, где встречается этот текст
    array_agg(review_id) as review_ids
FROM reviews
GROUP BY review_text
-- Ищем группы, где больше 5 одинаковых отзывов
HAVING COUNT(*) > 5
ORDER BY duplicate_count DESC
LIMIT 10;