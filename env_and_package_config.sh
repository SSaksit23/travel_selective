# =================
# .env file
# =================

# Amadeus API Credentials (Get from https://developers.amadeus.com)
AMADEUS_CLIENT_ID=your_amadeus_client_id_here
AMADEUS_CLIENT_SECRET=your_amadeus_client_secret_here

# Server Configuration
NODE_ENV=development
PORT=5000

# Database Configuration
DATABASE_URL=postgresql://username:password@localhost:5432/tour_operator_db

# Redis Configuration (for caching)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=

# JWT Secret for authentication
JWT_SECRET=your_super_secure_jwt_secret_here

# CORS Settings
CORS_ORIGIN=http://localhost:3000

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# =================
# package.json
# =================

{
  "name": "tour-operator-backend",
  "version": "1.0.0",
  "description": "Tour Operator Backend API with Amadeus Integration",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "jest",
    "test:watch": "jest --watch",
    "lint": "eslint .",
    "lint:fix": "eslint . --fix"
  },
  "keywords": ["travel", "amadeus", "tour-operator", "booking", "flights", "hotels"],
  "author": "Your Name",
  "license": "ISC",
  "dependencies": {
    "express": "^4.18.2",
    "amadeus": "^8.1.0",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "redis": "^4.6.8",
    "jsonwebtoken": "^9.0.2",
    "bcryptjs": "^2.4.3",
    "express-rate-limit": "^6.10.0",
    "helmet": "^7.0.0",
    "compression": "^1.7.4",
    "morgan": "^1.10.0",
    "joi": "^17.9.2",
    "axios": "^1.5.0",
    "moment": "^2.29.4",
    "node-cron": "^3.0.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.1",
    "jest": "^29.6.4",
    "supertest": "^6.3.3",
    "eslint": "^8.47.0",
    "prettier": "^3.0.2"
  },
  "engines": {
    "node": ">=16.0.0",
    "npm": ">=8.0.0"
  }
}

# =================
# docker-compose.yml (for local development)
# =================

version: '3.8'

services:
  # Backend API
  backend:
    build: .
    ports:
      - "5000:5000"
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/tour_operator_db
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    depends_on:
      - postgres
      - redis
    volumes:
      - .:/app
      - /app/node_modules
    command: npm run dev

  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=tour_operator_db
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  # Redis Cache
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  # Frontend (React)
  frontend:
    build:
      context: ./frontend
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://localhost:5000/api
    volumes:
      - ./frontend:/app
      - /app/node_modules
    depends_on:
      - backend

volumes:
  postgres_data:
  redis_data:

# =================
# Dockerfile
# =================

FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001

# Change ownership
RUN chown -R nodejs:nodejs /app
USER nodejs

EXPOSE 5000

CMD ["npm", "start"]

# =================
# Database Schema (PostgreSQL)
# =================

-- Users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(20),
    role VARCHAR(20) DEFAULT 'customer',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Search history
CREATE TABLE search_history (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    search_type VARCHAR(20) NOT NULL, -- 'flight' or 'hotel'
    search_params JSONB NOT NULL,
    results_count INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Bookings
CREATE TABLE bookings (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    booking_type VARCHAR(20) NOT NULL, -- 'flight', 'hotel', 'package'
    amadeus_booking_id VARCHAR(100),
    booking_data JSONB NOT NULL,
    total_price DECIMAL(10,2),
    currency VARCHAR(3),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Cached flight data
CREATE TABLE flight_cache (
    id SERIAL PRIMARY KEY,
    cache_key VARCHAR(255) UNIQUE NOT NULL,
    search_params JSONB NOT NULL,
    results JSONB NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Cached hotel data
CREATE TABLE hotel_cache (
    id SERIAL PRIMARY KEY,
    cache_key VARCHAR(255) UNIQUE NOT NULL,
    search_params JSONB NOT NULL,
    results JSONB NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Airport and city codes
CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    iata_code VARCHAR(3) UNIQUE,
    name VARCHAR(255) NOT NULL,
    city VARCHAR(100),
    country VARCHAR(100),
    country_code VARCHAR(2),
    type VARCHAR(20), -- 'airport' or 'city'
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    timezone VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pricing rules and markups
CREATE TABLE pricing_rules (
    id SERIAL PRIMARY KEY,
    rule_type VARCHAR(20) NOT NULL, -- 'flight' or 'hotel'
    route_pattern VARCHAR(100), -- e.g., 'MAD-*' for all flights from Madrid
    markup_type VARCHAR(20) NOT NULL, -- 'percentage' or 'fixed'
    markup_value DECIMAL(8,4) NOT NULL,
    currency VARCHAR(3),
    valid_from DATE,
    valid_to DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX idx_search_history_user_id ON search_history(user_id);
CREATE INDEX idx_search_history_created_at ON search_history(created_at);
CREATE INDEX idx_bookings_user_id ON bookings(user_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_flight_cache_expires_at ON flight_cache(expires_at);
CREATE INDEX idx_hotel_cache_expires_at ON hotel_cache(expires_at);
CREATE INDEX idx_locations_iata_code ON locations(iata_code);
CREATE INDEX idx_locations_type ON locations(type);

# =================
# Installation Commands
# =================

# 1. Clone or create project directory
mkdir tour-operator-system
cd tour-operator-system

# 2. Initialize backend
mkdir backend
cd backend
npm init -y

# 3. Install dependencies
npm install express amadeus cors dotenv redis jsonwebtoken bcryptjs express-rate-limit helmet compression morgan joi axios moment node-cron

# 4. Install dev dependencies
npm install --save-dev nodemon jest supertest eslint prettier

# 5. Set up frontend (React)
cd ..
npx create-react-app frontend
cd frontend
npm install axios react-datepicker react-router-dom @headlessui/react @heroicons/react

# 6. Set up database (if using Docker)
cd ..
docker-compose up -d postgres redis

# 7. Run database migrations
# (Create and run your SQL schema)

# 8. Start development servers
# Backend: npm run dev
# Frontend: npm start

# =================
# Production Deployment (Ubuntu Server)
# =================

# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 3. Install PostgreSQL
sudo apt install postgresql postgresql-contrib -y

# 4. Install Redis
sudo apt install redis-server -y

# 5. Install Nginx
sudo apt install nginx -y

# 6. Install PM2 for process management
sudo npm install -g pm2

# 7. Clone your repository
git clone your-repo-url tour-operator-system
cd tour-operator-system

# 8. Install dependencies
npm install --production

# 9. Set up environment variables
cp .env.example .env
nano .env  # Edit with production values

# 10. Start application with PM2
pm2 start ecosystem.config.js

# 11. Set up Nginx reverse proxy
sudo nano /etc/nginx/sites-available/tour-operator

# Example Nginx configuration:
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:3000;  # React app
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api {
        proxy_pass http://localhost:5000;  # API server
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

# 12. Enable site and restart Nginx
sudo ln -s /etc/nginx/sites-available/tour-operator /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# 13. Set up SSL with Let's Encrypt
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d your-domain.com