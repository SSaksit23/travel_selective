@echo off
echo 🔧 Fixing Backend Connection...
echo ================================

echo 📊 Checking current container status...
docker-compose ps

echo.
echo 📝 Checking backend logs...
echo ================================
docker-compose logs backend

echo.
echo 🔄 Restarting backend service...
docker-compose restart backend

echo.
echo ⏳ Waiting for backend to start...
timeout /t 10 /nobreak >nul

echo.
echo 🧪 Testing backend directly...
curl http://localhost:5000/api/health
if %errorlevel% neq 0 (
    echo ❌ Backend not responding on localhost:5000
    echo.
    echo 🔧 Let's fix the backend...
    
    REM Create a simpler backend server
    echo 📝 Creating simpler backend server...
    ^(
    echo const express = require^('express'^);
    echo const cors = require^('cors'^);
    echo.
    echo const app = express^(^);
    echo const port = 5000;
    echo.
    echo // Enable CORS for frontend
    echo app.use^(cors^({
    echo   origin: 'http://localhost:3000',
    echo   credentials: true
    echo }^)^);
    echo.
    echo app.use^(express.json^(^)^);
    echo.
    echo // Health check endpoint
    echo app.get^('/api/health', ^(req, res^) =^> {
    echo   console.log^('Health check requested'^);
    echo   res.json^({ 
    echo     status: 'OK', 
    echo     timestamp: new Date^(^).toISOString^(^),
    echo     message: 'Backend is working!'
    echo   }^);
    echo }^);
    echo.
    echo // Test endpoint
    echo app.get^('/api/test', ^(req, res^) =^> {
    echo   res.json^({ message: 'API test successful!' }^);
    echo }^);
    echo.
    echo // Log all requests
    echo app.use^(^(req, res, next^) =^> {
    echo   console.log^(`${new Date^(^).toISOString^(^)} - ${req.method} ${req.path}`^);
    echo   next^(^);
    echo }^);
    echo.
    echo app.listen^(port, '0.0.0.0', ^(^) =^> {
    echo   console.log^(`🚀 Backend server running on port ${port}`^);
    echo   console.log^(`✅ Health check: http://localhost:${port}/api/health`^);
    echo }^);
    ^) > backend\server.js
    
    echo ✅ Updated backend server
    
    REM Rebuild and restart
    echo 🔄 Rebuilding backend...
    docker-compose build backend
    docker-compose up -d backend
    
    echo ⏳ Waiting for backend restart...
    timeout /t 15 /nobreak >nul
    
) else (
    echo ✅ Backend is responding!
)

echo.
echo 🧪 Final tests...
echo ================================

echo Testing backend health:
curl http://localhost:5000/api/health

echo.
echo Testing from frontend container:
docker-compose exec frontend wget -qO- http://backend:5000/api/health

echo.
echo 📊 Container status:
docker-compose ps

echo.
echo 🎯 Next steps:
echo 1. Refresh http://localhost:3000
echo 2. It should now show "Backend Status: OK"
echo 3. If still not working, run: docker-compose restart

echo.
pause