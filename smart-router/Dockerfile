FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --uid 10001 --create-home --shell /usr/sbin/nologin router
COPY --chown=router:router src ./src
ENV PYTHONPATH=/app/src
USER 10001:10001
EXPOSE 8080
CMD ["python", "-m", "smart_router.main"]
