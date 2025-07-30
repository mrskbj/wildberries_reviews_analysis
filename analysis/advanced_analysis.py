# Скрипт для сложного анализа и визуализации.

# Вызываем необходимые библиотеки
import pandas as pd
import psycopg2
import matplotlib.pyplot as plt
import seaborn as sns

# Функция, к-я устанавливает соединение с базой данных PostgreSQL
def connect_to_db():
    try:
        conn = psycopg2.connect(
            host='localhost',
            port='5433',
            database='db_wb',
            user='postgres',
            password='my3sec5ret5pa7ssw3ord'
        )
        return conn
    except psycopg2.OperationalError as e:
        print(f"Ошибка подключения к базе данных: {e}")
        return None

# Функция находит аномальные отзывы, где оценка и тональность текста противоречат друг другу
def find_anomalous_reviews():
    conn = connect_to_db()
    if not conn:
        return

    print("Поиск аномальных отзывов")

    query = """
        SELECT
            r.review_id, p.product_name, r.rating, r.review_text, sa.sentiment_label
        FROM reviews r
        JOIN sentiment_analysis sa ON r.review_id = sa.review_id
        JOIN products p ON r.product_id = p.product_id;
    """
    
    try:
        df = pd.read_sql_query(query, conn)
        conn.close()

        anomaly_1 = df[(df['rating'] <= 2) & (df['sentiment_label'] == 'positive')]
        anomaly_2 = df[(df['rating'] == 5) & (df['sentiment_label'] == 'negative')]
        
        print(f"\nНайдено аномалий 'Низкая оценка / Позитивный текст': {len(anomaly_1)}")
        if not anomaly_1.empty:
            print(anomaly_1[['review_id', 'product_name', 'rating', 'review_text']].head())

        print(f"\nНайдено аномалий 'Высокая оценка / Негативный текст': {len(anomaly_2)}")
        if not anomaly_2.empty:
            print(anomaly_2[['review_id', 'product_name', 'rating', 'review_text']].head())
            
        return df

    except Exception as e:
        if conn:
            conn.close()
        print(f"Произошла ошибка: {e}")
        return None

# Функция строит графики и выводит числовые данные для анализа
def visualize_and_analyze_data(df):
    if df is None or df.empty:
        print("\nНет данных для анализа.")
        return
        
    print("\nАнализ распределений и построение графиков:")
    sns.set_theme(style="whitegrid")

    # 1. Анализ распределения по рейтингу
    rating_counts = df['rating'].value_counts().sort_index()
    print("\nРаспределение по рейтингу (1-5 звезд)")
    print(rating_counts)
    
    plt.figure(figsize=(10, 6))
    # Добавляем hue и legend=False, чтобы убрать предупреждение
    sns.countplot(x='rating', data=df, palette='viridis', hue='rating', legend=False)
    plt.title('Общее распределение оценок (1-5 звезд)', fontsize=16)
    plt.xlabel('Рейтинг', fontsize=12)
    plt.ylabel('Количество отзывов', fontsize=12)
    
    plt.savefig('img/ratings_distribution.png') # Сохраняем график
    plt.show()

    # 2. Анализ распределения по тональности
    sentiment_counts = df['sentiment_label'].value_counts()
    print("\nРаспределение по тональности")
    print(sentiment_counts)
    
    plt.figure(figsize=(10, 6))
    sns.countplot(x='sentiment_label', data=df, palette='rocket', order=['positive', 'neutral', 'negative'], hue='sentiment_label', legend=False)
    plt.title('Общее распределение тональности отзывов', fontsize=16)
    plt.xlabel('Тональность', fontsize=12)
    plt.ylabel('Количество отзывов', fontsize=12)
    
    plt.savefig('img/sentiment_distribution.png') # Сохраняем график
    plt.show()

if __name__ == "__main__":
    reviews_df = find_anomalous_reviews()
    # Вызываем функцию
    visualize_and_analyze_data(reviews_df)