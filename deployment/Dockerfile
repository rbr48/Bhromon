FROM nginx:alpine

# Copy custom Nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy build output to Nginx document root
COPY web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
