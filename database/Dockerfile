# Официальный образ PostgreSQL 17
FROM postgres:17

# Устанавливаем Python и pip, необходимые для plpython3u
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Копируем файл из папки config
COPY config/requirements.txt /tmp/requirements.txt

# Устанавливаем все Python-библиотеки, которые нужны для NLP
RUN pip install --no-cache-dir -r /tmp/requirements.txt --break-system-packages