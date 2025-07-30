# Импорт нужных библиотек
import pandas as pd
import psycopg2
from psycopg2.extras import execute_batch
from tqdm import tqdm
import os 

# Функция устанавливает соединение с базой данных PostgreSQL
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

# Функция очищает таблицы, загружает данные из CSV, вставляет их в БД и запускает NLP-обработку
def load_and_process_data(csv_file_path, batch_size=1000):
    # Извлечение и подготовка данных
    print(f"Чтение данных из {csv_file_path}...")
    try:
        df = pd.read_csv(csv_file_path, encoding='utf-8')
        # Очистка и нормализация данных
        df['product_name'] = df['name'].str.strip().str.lower()
        df['user_name'] = df['reviewerName'].str.strip().str.lower()
        df.rename(columns={'text': 'review_text', 'mark': 'rating'}, inplace=True)
        # Убираем строки с пустыми отзывами
        df.dropna(subset=['review_text', 'product_name', 'user_name'], inplace=True)
        print(f"CSV файл успешно прочитан, строк для загрузки: {len(df)}")
    except FileNotFoundError:
        print(f"Ошибка: CSV файл не найден по пути: {csv_file_path}")
        return
    except Exception as e:
        print(f"Ошибка при чтении или обработке CSV: {e}")
        return

    conn = connect_to_db()
    if not conn:
        return

    try:
        with conn.cursor() as cursor:
            # Очищаем таблицу перед загрузкой, чтобы не было дублей при повторном запуске 
            print("\nОчистка таблиц перед новой загрузкой")
            cursor.execute("""
                TRUNCATE TABLE products, users, reviews
                RESTART IDENTITY CASCADE;
            """)
            conn.commit()
            print("Таблицы успешно очищены")
            
            # Загрузка справочников: products и users
            print("\nЗагрузка products и users")

            # Готовим и вставляем уникальные товары
            products = [(name,) for name in df['product_name'].unique()]
            execute_batch(cursor, "INSERT INTO products (product_name) VALUES (%s) ON CONFLICT (product_name) DO NOTHING;", products)

            # Готовим и вставляем уникальных пользователей
            users = [(name,) for name in df['user_name'].unique()]
            execute_batch(cursor, "INSERT INTO users (user_name) VALUES (%s) ON CONFLICT (user_name) DO NOTHING;", users)
            
            conn.commit()
            print("products и users загружены.")

            # Получаем ID товаров и пользователей для сопоставления
            cursor.execute("SELECT product_name, product_id FROM products")
            product_map = dict(cursor.fetchall())
            
            cursor.execute("SELECT user_name, user_id FROM users")
            user_map = dict(cursor.fetchall())

            # Загрузка "сырых" отзывов
            print("\nЗагрузка отзывов")
            
            reviews_data = []
            for _, row in df.iterrows():
                product_id = product_map.get(row['product_name'])
                user_id = user_map.get(row['user_name'])
                if product_id and user_id:
                    reviews_data.append((
                        product_id,
                        user_id,
                        str(row['review_text']),
                        int(row['rating']),
                        pd.to_datetime(row.get('reviewDate', 'now')) # Используем дату, если есть
                    ))
            
            # Вставляем все отзывы одной командой
            execute_batch(cursor,
                """
                INSERT INTO reviews (product_id, user_id, review_text, rating, review_date)
                VALUES (%s, %s, %s, %s, %s);
                """,
                reviews_data,
                page_size=batch_size
            )
            conn.commit()
            print(f"{len(reviews_data)} отзывов успешно загружено.")
            
            # Запуск NLP-обработки в базе данных
            print("\nЗапуск NLP-обработки для новых отзывов в базе данных")
            
            # Получаем ID только что вставленных отзывов, у которых еще нет NLP-данных
            cursor.execute("""
                SELECT r.review_id FROM reviews r
                LEFT JOIN sentiment_analysis sa ON r.review_id = sa.review_id
                WHERE sa.review_id IS NULL;
            """)
            reviews_to_process = [item[0] for item in cursor.fetchall()]
            
            if not reviews_to_process:
                print("Все отзывы уже обработаны.")
                return

            # Вызываем SQL-функцию для каждого нового отзыва
            with tqdm(total=len(reviews_to_process), desc="NLP обработка") as pbar:
                for review_id in reviews_to_process:
                    cursor.execute("SELECT process_single_review(%s);", (review_id,))
                    conn.commit() # Коммит после каждого отзыва, чтобы видеть прогресс
                    pbar.update(1)
            
            print("NLP-обработка завершена!")

    except Exception as e:
        conn.rollback() # Откатываем транзакцию в случае любой ошибки
        print(f"\nПроизошла ошибка во время работы с базой данных: {e}")
    finally:
        conn.close()
        print("\nСоединение с базой данных закрыто.")


if __name__ == "__main__":
    # Путь к файлу
    CSV_FILE = "C:/Users/mrskb/Study/wildberries_reviews_analysis/data/prepared_data.csv"
    load_and_process_data(csv_file_path=CSV_FILE)