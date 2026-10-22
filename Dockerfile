
FROM nginx:alpine

LABEL maintainer="E-Waste Portal Team"
LABEL description="E-Waste Collection and Recycling Portal"

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
