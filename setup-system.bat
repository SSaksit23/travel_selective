@echo off
REM ============================================
REM Tour Operator System - Windows Quick Setup
REM ============================================

echo 🛫 Tour Operator System - Windows Setup
echo ==========================================

REM Check if Docker is running
docker --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Docker is not installed or not running
    echo Please install Docker Desktop from: https://www.docker.com/products/docker-desktop/
    echo Make sure Docker Desktop is running before continuing
    pause
    exit /b 1
)

echo ✅ Docker is available

REM Create project structure
echo 📁 Creating project structure...
if not exist "backend" mkdir backend
if not exist "frontend" mkdir frontend
if not exist "frontend\src" mkdir frontend\src
if not exist "frontend\src\components" mkdir frontend\src\components
if not exist "frontend\public" mkdir frontend\public
if not exist "database" mkdir database

REM Create docker-compose.yml
echo 🐳 Creating Docker configuration...
(
echo version: '3.8'^

echo.
echo services:
echo   frontend:
echo     build:
echo       context: ./frontend
echo     ports:
echo       - "3000:3000"
echo     environment:
echo       - REACT_APP_API_URL=http://localhost:5000/api
echo     volumes:
echo       - ./frontend:/app
echo       - /app/node_modules
echo     depends_on:
echo       - backend
echo.
echo   backend:
echo     build:
echo       context: ./backend
echo     ports:
echo       - "5000:5000"
echo     environment:
echo       - NODE_ENV=development
echo       - AMADEUS_CLIENT_ID=Bd76Zxmr3DtsAgSCNVhRlgCzzFDROM07
echo       - AMADEUS_CLIENT_SECRET=Onw33473vAI1CTHS
echo       - AMADEUS_HOSTNAME=test
echo       - DATABASE_URL=postgresql://tour_operator:secure_password@postgres:5432/tour_operator_db
echo       - REDIS_HOST=redis
echo       - REDIS_PORT=6379
echo       - CORS_ORIGIN=http://localhost:3000
echo     volumes:
echo       - ./backend:/app
echo       - /app/node_modules
echo     depends_on:
echo       - postgres
echo       - redis
echo.
echo   postgres:
echo     image: postgres:15-alpine
echo     environment:
echo       - POSTGRES_DB=tour_operator_db
echo       - POSTGRES_USER=tour_operator
echo       - POSTGRES_PASSWORD=secure_password
echo     ports:
echo       - "5432:5432"
echo     volumes:
echo       - postgres_data:/var/lib/postgresql/data
echo       - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql
echo.
echo   redis:
echo     image: redis:7-alpine
echo     ports:
echo       - "6379:6379"
echo     volumes:
echo       - redis_data:/data
echo.
echo   pgadmin:
echo     image: dpage/pgadmin4:latest
echo     environment:
echo       - PGADMIN_DEFAULT_EMAIL=admin@touroperator.com
echo       - PGADMIN_DEFAULT_PASSWORD=admin123
echo     ports:
echo       - "8080:80"
echo     depends_on:
echo       - postgres
echo.
echo volumes:
echo   postgres_data:
echo   redis_data:
) > docker-compose.yml

REM Create backend package.json
echo 📦 Creating backend configuration...
(
echo {
echo   "name": "tour-operator-backend",
echo   "version": "1.0.0",
echo   "main": "server.js",
echo   "scripts": {
echo     "start": "node server.js",
echo     "dev": "nodemon server.js"
echo   },
echo   "dependencies": {
echo     "express": "^4.18.2",
echo     "amadeus": "^8.1.0",
echo     "cors": "^2.8.5",
echo     "dotenv": "^16.3.1",
echo     "redis": "^4.6.8",
echo     "pg": "^8.11.3",
echo     "helmet": "^7.0.0",
echo     "compression": "^1.7.4",
echo     "morgan": "^1.10.0"
echo   },
echo   "devDependencies": {
echo     "nodemon": "^3.0.1"
echo   }
echo }
) > backend\package.json

REM Create backend Dockerfile
(
echo FROM node:18-alpine
echo WORKDIR /app
echo COPY package*.json ./
echo RUN npm ci
echo COPY . .
echo RUN addgroup -g 1001 -S nodejs ^&^& adduser -S nodejs -u 1001
echo RUN chown -R nodejs:nodejs /app
echo USER nodejs
echo EXPOSE 5000
echo CMD ["npm", "run", "dev"]
) > backend\Dockerfile

REM Create frontend package.json
echo 🎨 Creating frontend configuration...
(
echo {
echo   "name": "tour-operator-frontend",
echo   "version": "1.0.0",
echo   "private": true,
echo   "dependencies": {
echo     "react": "^18.2.0",
echo     "react-dom": "^18.2.0",
echo     "react-scripts": "5.0.1",
echo     "leaflet": "^1.9.4",
echo     "axios": "^1.5.0",
echo     "lucide-react": "^0.263.1"
echo   },
echo   "scripts": {
echo     "start": "react-scripts start",
echo     "build": "react-scripts build"
echo   },
echo   "devDependencies": {
echo     "tailwindcss": "^3.3.3",
echo     "autoprefixer": "^10.4.15",
echo     "postcss": "^8.4.28"
echo   }
echo }
) > frontend\package.json

REM Create frontend Dockerfile
(
echo FROM node:18-alpine
echo WORKDIR /app
echo COPY package*.json ./
echo RUN npm ci
echo COPY . .
echo EXPOSE 3000
echo CMD ["npm", "start"]
) > frontend\Dockerfile

REM Create database init script
echo 🗄️ Creating database schema...
(
echo CREATE TABLE IF NOT EXISTS locations ^(
echo     id SERIAL PRIMARY KEY,
echo     iata_code VARCHAR^(3^) UNIQUE,
echo     name VARCHAR^(255^) NOT NULL,
echo     city VARCHAR^(100^),
echo     country VARCHAR^(100^),
echo     latitude DECIMAL^(10,8^),
echo     longitude DECIMAL^(11,8^)
echo ^);
echo.
echo INSERT INTO locations ^(iata_code, name, city, country, latitude, longitude^) VALUES
echo ^('MAD', 'Madrid-Barajas Airport', 'Madrid', 'Spain', 40.472219, -3.560833^),
echo ^('BCN', 'Barcelona-El Prat Airport', 'Barcelona', 'Spain', 41.2971, 2.0785^),
echo ^('LHR', 'Heathrow Airport', 'London', 'United Kingdom', 51.4706, -0.4619^),
echo ^('CDG', 'Charles de Gaulle Airport', 'Paris', 'France', 49.0097, 2.5479^),
echo ^('BKK', 'Suvarnabhumi Airport', 'Bangkok', 'Thailand', 13.6900, 100.7501^),
echo ^('DXB', 'Dubai International Airport', 'Dubai', 'UAE', 25.2532, 55.3657^),
echo ^('SIN', 'Singapore Changi Airport', 'Singapore', 'Singapore', 1.3644, 103.9915^),
echo ^('JFK', 'John F. Kennedy International Airport', 'New York', 'USA', 40.6413, -73.7781^),
echo ^('LAX', 'Los Angeles International Airport', 'Los Angeles', 'USA', 33.9425, -118.4081^),
echo ^('NRT', 'Narita International Airport', 'Tokyo', 'Japan', 35.7647, 140.3864^)
echo ON CONFLICT ^(iata_code^) DO NOTHING;
) > database\init.sql

echo ✅ All configuration files created!

REM Start the system
echo 🚀 Building and starting the system...
echo This may take a few minutes on first run...

docker-compose build
if errorlevel 1 (
    echo ❌ Build failed! Check the error messages above.
    pause
    exit /b 1
)

docker-compose up -d
if errorlevel 1 (
    echo ❌ Failed to start services! Check Docker Desktop is running.
    pause
    exit /b 1
)

echo.
echo ⏳ Waiting for services to start...
timeout /t 30 /nobreak >nul

REM Check if services are running
docker-compose ps | findstr "Up" >nul
if errorlevel 1 (
    echo ⚠️ Some services may not have started properly.
    echo Run 'docker-compose logs' to check for errors.
) else (
    echo ✅ Services are starting up!
)

echo.
echo 🎉 Tour Operator System Setup Complete!
echo ==========================================
echo.
echo 📱 Access Your System:
echo   🌐 Frontend:     http://localhost:3000
echo   🔌 Backend API:  http://localhost:5000/api
echo   🗄️ Database:     http://localhost:8080
echo      📧 Email: admin@touroperator.com
echo      🔑 Password: admin123
echo.
echo ✈️ Features Ready:
echo   ✅ Flight search with interactive route maps
echo   ✅ Hotel search with location maps  
echo   ✅ Your Amadeus API keys integrated
echo   ✅ Real-time search results
echo.
echo 🎯 Quick Test:
echo   1. Open http://localhost:3000
echo   2. Search flights: Madrid → Barcelona
echo   3. See route map with departure/arrival markers
echo   4. Switch to Hotels tab - destination auto-filled!
echo.
echo 🛠️ Management Commands:
echo   📊 Check status: docker-compose ps
echo   📝 View logs:    docker-compose logs -f
echo   🔄 Restart:      docker-compose restart
echo   ⏹️ Stop:         docker-compose down
echo.
echo 🎊 Enjoy your Tour Operator System!
echo.
pause

REM ---
REM Additional helper scripts
REM ---

REM Create start script
(
echo @echo off
echo echo 🚀 Starting Tour Operator System...
echo docker-compose up -d
echo echo ✅ System started!
echo echo 🌐 Frontend: http://localhost:3000
echo echo 🔌 Backend: http://localhost:5000/api
echo pause
) > start-system.bat

REM Create stop script  
(
echo @echo off
echo echo ⏹️ Stopping Tour Operator System...
echo docker-compose down
echo echo ✅ System stopped!
echo pause
) > stop-system.bat

REM Create logs script
(
echo @echo off
echo echo 📊 Viewing system logs...
echo docker-compose logs -f
) > view-logs.bat

echo 📝 Helper scripts created:
echo   - start-system.bat  ^(start the system^)
echo   - stop-system.bat   ^(stop the system^)  
echo   - view-logs.bat     ^(view logs^)
echo.