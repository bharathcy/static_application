FROM nginx:alpine

# Copy the static site into Nginx's default web root
COPY index.html style.css /usr/share/nginx/html/

EXPOSE 80
