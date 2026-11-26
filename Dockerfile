# Streamlit front door with the Terraform CLI bundled (Render, local Docker, any container host).
#   docker build -t dbt-project-factory .
#   docker run -p 8501:8501 dbt-project-factory
#
# Without a remote backend, state lives inside the container and is lost when
# it restarts. That suits create/destroy in one sitting, not ongoing management.
FROM python:3.11-slim

ARG TF_VERSION=1.14.0
ARG TF_ARCH=amd64
RUN apt-get update && apt-get install -y --no-install-recommends unzip ca-certificates curl \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip" -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip terraform -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && terraform -version \
    && apt-get purge -y unzip curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY app/requirements.txt app/requirements.txt
RUN pip install --no-cache-dir -r app/requirements.txt

COPY app app
COPY scripts scripts
COPY modules modules
COPY projects/example projects/example

EXPOSE 8501
CMD ["sh", "-c", "streamlit run app/streamlit_app.py --server.port=${PORT:-8501} --server.address=0.0.0.0"]
