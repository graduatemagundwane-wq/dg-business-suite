FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HOST=0.0.0.0 PORT=8080 IRVINAERO_DEMO=0
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir -r requirements.txt
COPY server.py ./
COPY static/ ./static/
EXPOSE 8080
CMD ["python", "server.py"]
