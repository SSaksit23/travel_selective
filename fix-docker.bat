@echo off
echo 🔧 Fixing Docker build issue...

REM Stop any running containers
docker-compose down

REM Fix backend Dockerfile
echo 📦 Updating backend Dockerfile...
(
echo FROM node:18-alpine
echo WORKDIR /app
echo COPY package*.json ./
echo RUN npm install
echo COPY . .
echo RUN addgroup -g 1001 -S nodejs ^&^& adduser -S nodejs -u 1001
echo RUN chown -R nodejs:nodejs /app
echo USER nodejs
echo EXPOSE 5000
echo CMD ["npm", "run", "dev"]
) > backend\Dockerfile

REM Fix frontend Dockerfile  
echo 🎨 Updating frontend Dockerfile...
(
echo FROM node:18-alpine
echo WORKDIR /app
echo COPY package*.json ./
echo RUN npm install
echo COPY . .
echo EXPOSE 3000
echo CMD ["npm", "start"]
) > frontend\Dockerfile

REM Add the missing source files

REM Create frontend public/index.html
echo 📄 Creating frontend HTML file...
if not exist "frontend\public" mkdir frontend\public
(
echo ^<!DOCTYPE html^>
echo ^<html lang="en"^>
echo   ^<head^>
echo     ^<meta charset="utf-8" /^>
echo     ^<meta name="viewport" content="width=device-width, initial-scale=1" /^>
echo     ^<title^>Tour Operator System^</title^>
echo     ^<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" /^>
echo   ^</head^>
echo   ^<body^>
echo     ^<div id="root"^>^</div^>
echo   ^</body^>
echo ^</html^>
) > frontend\public\index.html

REM Create frontend src files
echo ⚛️ Creating React components...
if not exist "frontend\src" mkdir frontend\src

REM Create index.css
(
echo @tailwind base;
echo @tailwind components;
echo @tailwind utilities;
echo.
echo body {
echo   margin: 0;
echo   font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
echo   background-color: #f9fafb;
echo }
echo.
echo .custom-div-icon {
echo   background: transparent;
echo   border: none;
echo   font-size: 20px;
echo   display: flex;
echo   align-items: center;
echo   justify-content: center;
echo }
) > frontend\src\index.css

REM Create index.js
(
echo import React from 'react';
echo import ReactDOM from 'react-dom/client';
echo import './index.css';
echo import App from './App';
echo.
echo const root = ReactDOM.createRoot^(document.getElementById^('root'^)^);
echo root.render^(^<App /^>^);
) > frontend\src\index.js

REM Create App.js
(
echo import React, { useState } from 'react';
echo.
echo function App^(^) {
echo   const [message, setMessage] = useState^('Loading...'^);
echo.
echo   React.useEffect^(^(^) =^> {
echo     fetch^('/api/health'^)
echo       .then^(res =^> res.json^(^)^)
echo       .then^(data =^> setMessage^(`Backend Status: ${data.status}`^)^)
echo       .catch^(^(^) =^> setMessage^('Backend connection failed'^)^);
echo   }, []^);
echo.
echo   return ^(
echo     ^<div style={{padding: '20px', textAlign: 'center'}}^>
echo       ^<h1^>✈️ Tour Operator System^</h1^>
echo       ^<p^>{message}^</p^>
echo       ^<p^>Frontend is running! Backend integration coming next...^</p^>
echo     ^</div^>
echo   ^);
echo }
echo.
echo export default App;
) > frontend\src\App.js

REM Create tailwind config files
(
echo module.exports = {
echo   content: ["./src/**/*.{js,jsx,ts,tsx}"],
echo   theme: { extend: {} },
echo   plugins: [],
echo }
) > frontend\tailwind.config.js

(
echo module.exports = {
echo   plugins: {
echo     tailwindcss: {},
echo     autoprefixer: {},
echo   },
echo }
) > frontend\postcss.config.js

REM Create simplified backend server.js
echo 🚀 Creating backend server...
(
echo const express = require^('express'^);
echo const cors = require^('cors'^);
echo.
echo const app = express^(^);
echo const port = process.env.PORT ^|^| 5000;
echo.
echo app.use^(cors^(^)^);
echo app.use^(express.json^(^)^);
echo.
echo // Health check endpoint
echo app.get^('/api/health', ^(req, res^) =^> {
echo   res.json^({ 
echo     status: 'OK', 
echo     timestamp: new Date^(^).toISOString^(^),
echo     message: 'Tour Operator Backend is running!'
echo   }^);
echo }^);
echo.
echo // Test endpoint
echo app.get^('/api/test', ^(req, res^) =^> {
echo   res.json^({ message: 'API is working!' }^);
echo }^);
echo.
echo app.listen^(port, ^(^) =^> {
echo   console.log^(`🚀 Server running on port ${port}`^);
echo   console.log^('✅ Basic backend is ready!'^);
echo }^);
) > backend\server.js

echo ✅ All files updated and created!
echo.
echo 🔄 Rebuilding containers...
docker-compose build --no-cache

if %errorlevel% equ 0 (
    echo ✅ Build successful!
    echo 🚀 Starting services...
    docker-compose up -d
    
    echo.
    echo ⏳ Waiting for services...
    timeout /t 20 /nobreak >nul
    
    echo.
    echo 🎉 System should be ready!
    echo 🌐 Frontend: http://localhost:3000
    echo 🔌 Backend:  http://localhost:5000/api/health
    echo.
    echo 📋 Next steps:
    echo 1. Open http://localhost:3000 to see if frontend loads
    echo 2. Open http://localhost:5000/api/health to test backend
    echo 3. If both work, we'll add the Amadeus integration
    
) else (
    echo ❌ Build failed again. Let's try a different approach...
    echo.
    echo 🔧 Alternative solution:
    echo 1. Stop Docker: docker-compose down
    echo 2. Install Docker Desktop from: https://www.docker.com/products/docker-desktop/
    echo 3. Make sure Docker Desktop is running
    echo 4. Try running this script again
)

echo.
pause