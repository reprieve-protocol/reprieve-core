FROM node:20-alpine AS app

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

EXPOSE 3001

CMD ["npm", "run", "start:api:prod"]
