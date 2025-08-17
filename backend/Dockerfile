FROM python:3.9-slim
# Cria diretório para o app
WORKDIR /app
# Copia os arquivos para dentro da imagem
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
# Expõe a porta onde o Flask roda internamente
EXPOSE 5000
# Comando de execução
CMD ["python", "app.py"]
