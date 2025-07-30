-- Оптимизация аналитических запросов с помощью материализованных представлений.

-- Создаем материализованное представление с полной аналитикой по каждому товару.
CREATE MATERIALIZED VIEW IF NOT EXISTS product_analytics_summary AS
SELECT
    p.product_id,
    p.product_name,
    COUNT(r.review_id) AS total_reviews,
    ROUND(AVG(r.rating), 2) AS avg_rating,
    COUNT(CASE WHEN sa.sentiment_label = 'positive' THEN 1 END) AS positive_count,
    COUNT(CASE WHEN sa.sentiment_label = 'neutral' THEN 1 END) AS neutral_count,
    COUNT(CASE WHEN sa.sentiment_label = 'negative' THEN 1 END) AS negative_count
FROM
    products p
JOIN reviews r ON p.product_id = r.product_id
JOIN sentiment_analysis sa ON r.review_id = sa.review_id
GROUP BY
    p.product_id, p.product_name;

-- Создаем индекс для быстрого поиска по представлению
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_analytics_summary_product_id ON product_analytics_summary(product_id);

-- 2. Проверяем как быстро выполняются аналитические запросы 

-- Пример: получение топ-10 товаров по рейтингу
SELECT product_name, avg_rating, total_reviews
FROM product_analytics_summary
WHERE total_reviews > 10
ORDER BY avg_rating DESC
LIMIT 10;

-- 3. Обновление данные в представлении (обновляем кэш)
REFRESH MATERIALIZED VIEW product_analytics_summary;
