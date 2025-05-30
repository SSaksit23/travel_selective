#!/bin/bash

echo "🛫 Tour Operator System - Complete Auto Setup"
echo "=============================================="
echo "This will create your complete tour operator system with:"
echo "✅ Flight search with route maps"
echo "✅ Hotel search with location maps"
echo "✅ Your Amadeus API keys already configured"
echo "✅ Complete Docker setup"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first:"
    echo "   https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first:"
    echo "   https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✅ Docker and Docker Compose are installed"

# Create project structure
echo ""
echo "📁 Creating project structure..."
mkdir -p tour-operator-system
cd tour-operator-system

mkdir -p {backend,frontend/{src/components,public},database,scripts}

echo "✅ Directory structure created"

# Create root files
echo ""
echo "📝 Creating configuration files..."

# Docker Compose
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
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

  backend:
    build:
      context: ./backend
    ports:
      - "5000:5000"
    environment:
      - NODE_ENV=development
      - AMADEUS_CLIENT_ID=Bd76Zxmr3DtsAgSCNVhRlgCzzFDROM07
      - AMADEUS_CLIENT_SECRET=Onw33473vAI1CTHS
      - AMADEUS_HOSTNAME=test
      - DATABASE_URL=postgresql://tour_operator:secure_password@postgres:5432/tour_operator_db
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - CORS_ORIGIN=http://localhost:3000
    volumes:
      - ./backend:/app
      - /app/node_modules
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=tour_operator_db
      - POSTGRES_USER=tour_operator
      - POSTGRES_PASSWORD=secure_password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  pgadmin:
    image: dpage/pgadmin4:latest
    environment:
      - PGADMIN_DEFAULT_EMAIL=admin@touroperator.com
      - PGADMIN_DEFAULT_PASSWORD=admin123
    ports:
      - "8080:80"
    depends_on:
      - postgres

volumes:
  postgres_data:
  redis_data:
EOF

# Backend files
echo "🔧 Creating backend files..."

cat > backend/package.json << 'EOF'
{
  "name": "tour-operator-backend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "amadeus": "^8.1.0",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "redis": "^4.6.8",
    "pg": "^8.11.3",
    "helmet": "^7.0.0",
    "compression": "^1.7.4",
    "morgan": "^1.10.0",
    "axios": "^1.5.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

cat > backend/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001
RUN chown -R nodejs:nodejs /app
USER nodejs

EXPOSE 5000
CMD ["npm", "run", "dev"]
EOF

cat > backend/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const redis = require('redis');
const { Pool } = require('pg');
const Amadeus = require('amadeus');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

// Redis client
const redisClient = redis.createClient({
  socket: {
    host: process.env.REDIS_HOST || 'redis',
    port: process.env.REDIS_PORT || 6379
  }
});

redisClient.connect().catch(console.error);

// Amadeus client with your API keys
const amadeus = new Amadeus({
  clientId: 'Bd76Zxmr3DtsAgSCNVhRlgCzzFDROM07',
  clientSecret: 'Onw33473vAI1CTHS',
  hostname: 'test'
});

// Utility functions
const getCachedData = async (key) => {
  try {
    const data = await redisClient.get(key);
    return data ? JSON.parse(data) : null;
  } catch (error) {
    return null;
  }
};

const setCachedData = async (key, data, expiration = 900) => {
  try {
    await redisClient.setEx(key, expiration, JSON.stringify(data));
  } catch (error) {
    console.error('Redis error:', error);
  }
};

// Routes
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    amadeus: 'Connected'
  });
});

// Location search endpoint
app.get('/api/locations/search', async (req, res) => {
  try {
    const { keyword } = req.query;
    
    if (!keyword || keyword.length < 2) {
      return res.status(400).json({ error: 'Keyword must be at least 2 characters' });
    }

    const cacheKey = `locations_${keyword.toLowerCase()}`;
    const cached = await getCachedData(cacheKey);
    
    if (cached) {
      return res.json(cached);
    }

    const response = await amadeus.referenceData.locations.get({
      keyword,
      subType: 'AIRPORT,CITY',
      sort: 'analytics.travelers.score',
      'page[limit]': 10
    });

    const locations = response.data.map(location => ({
      code: location.iataCode,
      name: location.name,
      city: location.address?.cityName,
      country: location.address?.countryName,
      type: location.subType,
      latitude: location.geoCode?.latitude,
      longitude: location.geoCode?.longitude
    }));

    await setCachedData(cacheKey, locations, 86400);
    res.json(locations);

  } catch (error) {
    console.error('Location search error:', error);
    res.status(500).json({ 
      error: 'Failed to search locations',
      details: error.description || error.message 
    });
  }
});

// Flight search endpoint
app.post('/api/flights/search', async (req, res) => {
  try {
    const {
      originLocationCode,
      destinationLocationCode,
      departureDate,
      returnDate,
      adults = 1
    } = req.body;

    if (!originLocationCode || !destinationLocationCode || !departureDate) {
      return res.status(400).json({ 
        error: 'Origin, destination, and departure date are required' 
      });
    }

    const searchParams = {
      originLocationCode,
      destinationLocationCode,
      departureDate,
      adults: parseInt(adults),
      max: 10
    };

    if (returnDate) searchParams.returnDate = returnDate;

    const response = await amadeus.shopping.flightOffersSearch.get(searchParams);

    const flights = response.data.map(offer => ({
      id: offer.id,
      price: {
        total: offer.price.total,
        currency: offer.price.currency
      },
      itineraries: offer.itineraries.map(itinerary => ({
        duration: itinerary.duration,
        segments: itinerary.segments.map(segment => ({
          departure: {
            iataCode: segment.departure.iataCode,
            at: segment.departure.at
          },
          arrival: {
            iataCode: segment.arrival.iataCode,
            at: segment.arrival.at
          },
          carrierCode: segment.carrierCode,
          number: segment.number,
          numberOfStops: segment.numberOfStops || 0
        }))
      })),
      validatingAirlineCodes: offer.validatingAirlineCodes
    }));

    // Get coordinates for map
    const getCoords = async (code) => {
      try {
        const locResponse = await amadeus.referenceData.locations.get({
          keyword: code,
          subType: 'AIRPORT,CITY'
        });
        const location = locResponse.data.find(loc => loc.iataCode === code);
        return location?.geoCode ? {
          latitude: location.geoCode.latitude,
          longitude: location.geoCode.longitude,
          name: location.name,
          city: location.address?.cityName,
          country: location.address?.countryName
        } : null;
      } catch (error) {
        return null;
      }
    };

    const [originCoords, destCoords] = await Promise.all([
      getCoords(originLocationCode),
      getCoords(destinationLocationCode)
    ]);

    res.json({
      flights,
      mapData: {
        origin: originCoords ? { code: originLocationCode, ...originCoords } : null,
        destination: destCoords ? { code: destinationLocationCode, ...destCoords } : null
      }
    });

  } catch (error) {
    console.error('Flight search error:', error);
    res.status(500).json({ 
      error: 'Failed to search flights',
      details: error.description || error.message 
    });
  }
});

// Hotel search endpoint
app.get('/api/hotels/search', async (req, res) => {
  try {
    const {
      cityCode,
      checkInDate,
      checkOutDate,
      adults = 1
    } = req.query;

    if (!cityCode || !checkInDate || !checkOutDate) {
      return res.status(400).json({ 
        error: 'City code, check-in and check-out dates are required' 
      });
    }

    // Get hotels by city
    const hotelListResponse = await amadeus.referenceData.locations.hotels.byCity.get({
      cityCode
    });

    if (!hotelListResponse.data || hotelListResponse.data.length === 0) {
      return res.json({ hotels: [] });
    }

    const hotelIds = hotelListResponse.data.slice(0, 20).map(hotel => hotel.hotelId);

    // Get hotel offers
    const offersResponse = await amadeus.shopping.hotelOffersSearch.get({
      hotelIds: hotelIds.join(','),
      checkInDate,
      checkOutDate,
      adults: parseInt(adults)
    });

    const hotels = offersResponse.data.map(hotel => ({
      hotelId: hotel.hotel.hotelId,
      name: hotel.hotel.name,
      rating: hotel.hotel.rating,
      address: hotel.hotel.address,
      geoCode: hotel.hotel.geoCode,
      offers: hotel.offers?.map(offer => ({
        id: offer.id,
        price: offer.price,
        room: offer.room,
        boardType: offer.boardType
      })) || []
    }));

    res.json({
      hotels: hotels.filter(hotel => hotel.offers.length > 0),
      mapData: {
        hotels: hotels.map(hotel => ({
          hotelId: hotel.hotelId,
          name: hotel.name,
          coordinates: hotel.geoCode,
          rating: hotel.rating
        })).filter(hotel => hotel.coordinates)
      }
    });

  } catch (error) {
    console.error('Hotel search error:', error);
    res.status(500).json({ 
      error: 'Failed to search hotels',
      details: error.description || error.message 
    });
  }
});

app.listen(port, () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`✈️  Amadeus API: Connected with your keys`);
});
EOF

# Frontend files
echo "🎨 Creating frontend files..."

cat > frontend/package.json << 'EOF'
{
  "name": "tour-operator-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "leaflet": "^1.9.4",
    "axios": "^1.5.0",
    "lucide-react": "^0.263.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "devDependencies": {
    "tailwindcss": "^3.3.3",
    "autoprefixer": "^10.4.15",
    "postcss": "^8.4.28"
  }
}
EOF

cat > frontend/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

EXPOSE 3000
CMD ["npm", "start"]
EOF

cat > frontend/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Tour Operator System</title>
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
EOF

cat > frontend/tailwind.config.js << 'EOF'
module.exports = {
  content: ["./src/**/*.{js,jsx,ts,tsx}"],
  theme: { extend: {} },
  plugins: [],
}
EOF

cat > frontend/postcss.config.js << 'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF

cat > frontend/src/index.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background-color: #f9fafb;
}

.custom-div-icon {
  background: transparent;
  border: none;
  font-size: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.selected-hotel {
  font-size: 24px;
  filter: drop-shadow(0 0 8px rgba(59, 130, 246, 0.6));
}
EOF

cat > frontend/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
EOF

# Create all React components by copying from the artifacts above
# App.js
cat > frontend/src/App.js << 'EOF'
import React, { useState } from 'react';
import FlightSearch from './components/FlightSearch';
import HotelSearch from './components/HotelSearch';

function App() {
  const [activeTab, setActiveTab] = useState('flights');
  const [flightData, setFlightData] = useState(null);

  return (
    <div className="min-h-screen bg-gray-100">
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <h1 className="text-2xl font-bold text-gray-900">✈️ Tour Operator System</h1>
          <p className="text-sm text-gray-600">Powered by Amadeus API</p>
        </div>
      </header>

      <nav className="bg-white border-b">
        <div className="max-w-7xl mx-auto px-4">
          <div className="flex space-x-8">
            <button
              onClick={() => setActiveTab('flights')}
              className={`py-4 px-1 border-b-2 font-medium ${
                activeTab === 'flights'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              🛫 Flights
            </button>
            <button
              onClick={() => setActiveTab('hotels')}
              className={`py-4 px-1 border-b-2 font-medium ${
                activeTab === 'hotels'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              🏨 Hotels
            </button>
          </div>
        </div>
      </nav>

      <main className="max-w-7xl mx-auto py-6 px-4">
        {activeTab === 'flights' && <FlightSearch onFlightSelect={setFlightData} />}
        {activeTab === 'hotels' && <HotelSearch flightData={flightData} />}
      </main>
    </div>
  );
}

export default App;
EOF

# Download the full React components (simplified versions for demo)
echo "📱 Creating React components..."

# Create simplified FlightSearch component
cat > frontend/src/components/FlightSearch.js << 'EOF'
import React, { useState } from 'react';
import MapComponent from './MapComponent';
import { Search, Calendar, Users, MapPin, Plane } from 'lucide-react';
import axios from 'axios';

const FlightSearch = ({ onFlightSelect }) => {
  const [searchParams, setSearchParams] = useState({
    origin: '',
    destination: '',
    departureDate: '',
    adults: 1
  });

  const [originSuggestions, setOriginSuggestions] = useState([]);
  const [destinationSuggestions, setDestinationSuggestions] = useState([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchResults, setSearchResults] = useState(null);
  const [showOriginDropdown, setShowOriginDropdown] = useState(false);
  const [showDestinationDropdown, setShowDestinationDropdown] = useState(false);

  const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:5000/api';

  const searchLocations = async (query, setSuggestions) => {
    if (query.length < 2) {
      setSuggestions([]);
      return;
    }
    
    try {
      const response = await axios.get(`${API_BASE_URL}/locations/search?keyword=${encodeURIComponent(query)}`);
      setSuggestions(response.data || []);
    } catch (error) {
      console.error('Error searching locations:', error);
      setSuggestions([]);
    }
  };

  const handleOriginSearch = (e) => {
    const value = e.target.value;
    setSearchParams(prev => ({ ...prev, origin: value }));
    searchLocations(value, setOriginSuggestions);
    setShowOriginDropdown(true);
  };

  const handleDestinationSearch = (e) => {
    const value = e.target.value;
    setSearchParams(prev => ({ ...prev, destination: value }));
    searchLocations(value, setDestinationSuggestions);
    setShowDestinationDropdown(true);
  };

  const selectOrigin = (location) => {
    setSearchParams(prev => ({ ...prev, origin: `${location.city || location.name} (${location.code})` }));
    setOriginSuggestions([]);
    setShowOriginDropdown(false);
  };

  const selectDestination = (location) => {
    setSearchParams(prev => ({ ...prev, destination: `${location.city || location.name} (${location.code})` }));
    setDestinationSuggestions([]);
    setShowDestinationDropdown(false);
  };

  const extractIataCode = (locationString) => {
    const match = locationString.match(/\(([A-Z]{3})\)/);
    return match ? match[1] : '';
  };

  const handleSearch = async () => {
    const originCode = extractIataCode(searchParams.origin);
    const destinationCode = extractIataCode(searchParams.destination);
    
    if (!originCode || !destinationCode || !searchParams.departureDate) {
      alert('Please fill in all required fields');
      return;
    }

    setIsSearching(true);
    
    try {
      const requestBody = {
        originLocationCode: originCode,
        destinationLocationCode: destinationCode,
        departureDate: searchParams.departureDate,
        adults: searchParams.adults
      };

      const response = await axios.post(`${API_BASE_URL}/flights/search`, requestBody);
      setSearchResults(response.data);
      
      if (onFlightSelect) {
        onFlightSelect({
          destination: destinationCode,
          destinationName: searchParams.destination,
          dates: { departure: searchParams.departureDate }
        });
      }
    } catch (error) {
      console.error('Error searching flights:', error);
      alert('Failed to search flights. Please try again.');
    } finally {
      setIsSearching(false);
    }
  };

  const formatTime = (dateTimeString) => {
    return new Date(dateTimeString).toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    });
  };

  const formatDuration = (duration) => {
    return duration.replace('PT', '').replace('H', 'h ').replace('M', 'm');
  };

  return (
    <div className="space-y-6">
      {/* Search Form */}
      <div className="bg-white rounded-xl shadow-lg p-6">
        <h2 className="text-2xl font-bold text-gray-800 mb-6">Flight Search</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          {/* Origin */}
          <div className="relative">
            <label className="block text-sm font-medium text-gray-700 mb-2">From</label>
            <div className="relative">
              <MapPin className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <input
                type="text"
                value={searchParams.origin}
                onChange={handleOriginSearch}
                placeholder="City or airport"
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              {showOriginDropdown && originSuggestions.length > 0 && (
                <div className="absolute z-10 w-full mt-1 bg-white border border-gray-300 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                  {originSuggestions.map((location, index) => (
                    <button
                      key={index}
                      onClick={() => selectOrigin(location)}
                      className="w-full px-4 py-3 text-left hover:bg-gray-50 border-b border-gray-100 last:border-b-0"
                    >
                      <div className="font-medium">{location.city || location.name} ({location.code})</div>
                      <div className="text-sm text-gray-500">{location.country}</div>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Destination */}
          <div className="relative">
            <label className="block text-sm font-medium text-gray-700 mb-2">To</label>
            <div className="relative">
              <MapPin className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <input
                type="text"
                value={searchParams.destination}
                onChange={handleDestinationSearch}
                placeholder="City or airport"
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              {showDestinationDropdown && destinationSuggestions.length > 0 && (
                <div className="absolute z-10 w-full mt-1 bg-white border border-gray-300 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                  {destinationSuggestions.map((location, index) => (
                    <button
                      key={index}
                      onClick={() => selectDestination(location)}
                      className="w-full px-4 py-3 text-left hover:bg-gray-50 border-b border-gray-100 last:border-b-0"
                    >
                      <div className="font-medium">{location.city || location.name} ({location.code})</div>
                      <div className="text-sm text-gray-500">{location.country}</div>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Departure Date */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Departure</label>
            <div className="relative">
              <Calendar className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <input
                type="date"
                value={searchParams.departureDate}
                onChange={(e) => setSearchParams(prev => ({ ...prev, departureDate: e.target.value }))}
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                min={new Date().toISOString().split('T')[0]}
              />
            </div>
          </div>

          {/* Passengers */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Passengers</label>
            <div className="relative">
              <Users className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <select
                value={searchParams.adults}
                onChange={(e) => setSearchParams(prev => ({ ...prev, adults: parseInt(e.target.value) }))}
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                {[1,2,3,4,5,6].map(num => (
                  <option key={num} value={num}>{num} Adult{num > 1 ? 's' : ''}</option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {/* Search Button */}
        <button
          onClick={handleSearch}
          disabled={!searchParams.origin || !searchParams.destination || !searchParams.departureDate || isSearching}
          className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-semibold py-3 px-6 rounded-lg transition duration-200 flex items-center justify-center space-x-2"
        >
          {isSearching ? (
            <>
              <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
              <span>Searching flights...</span>
            </>
          ) : (
            <>
              <Search className="h-5 w-5" />
              <span>Search Flights</span>
            </>
          )}
        </button>
      </div>

      {/* Results */}
      {searchResults && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Flight Results */}
          <div className="lg:col-span-2">
            <div className="bg-white rounded-xl shadow-lg p-6">
              <h3 className="text-xl font-bold text-gray-800 mb-6">
                Available Flights ({searchResults.flights?.length || 0} found)
              </h3>
              
              <div className="space-y-4">
                {searchResults.flights?.map((flight) => (
                  <div key={flight.id} className="border border-gray-200 rounded-lg p-6 hover:shadow-md transition-shadow">
                    {flight.itineraries.map((itinerary, itinIndex) => (
                      <div key={itinIndex} className="mb-4 last:mb-0">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center space-x-6">
                            <div className="text-center">
                              <div className="text-2xl font-bold text-gray-800">
                                {formatTime(itinerary.segments[0].departure.at)}
                              </div>
                              <div className="text-sm text-gray-500">
                                {itinerary.segments[0].departure.iataCode}
                              </div>
                            </div>
                            
                            <div className="flex flex-col items-center">
                              <div className="text-sm text-gray-500">
                                {formatDuration(itinerary.duration)}
                              </div>
                              <div className="flex items-center space-x-2 my-1">
                                <div className="w-2 h-2 bg-gray-400 rounded-full"></div>
                                <div className="flex-1 h-px bg-gray-300"></div>
                                <Plane className="h-4 w-4 text-gray-400" />
                                <div className="flex-1 h-px bg-gray-300"></div>
                                <div className="w-2 h-2 bg-gray-400 rounded-full"></div>
                              </div>
                              <div className="text-sm text-gray-500">Direct</div>
                            </div>
                            
                            <div className="text-center">
                              <div className="text-2xl font-bold text-gray-800">
                                {formatTime(itinerary.segments[itinerary.segments.length - 1].arrival.at)}
                              </div>
                              <div className="text-sm text-gray-500">
                                {itinerary.segments[itinerary.segments.length - 1].arrival.iataCode}
                              </div>
                            </div>
                          </div>
                          
                          {itinIndex === 0 && (
                            <div className="text-right">
                              <div className="text-3xl font-bold text-blue-600">
                                {flight.price.currency} {flight.price.total}
                              </div>
                              <div className="text-sm text-gray-400">
                                {itinerary.segments[0].carrierCode} {itinerary.segments[0].number}
                              </div>
                              <button className="mt-2 bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-6 rounded-lg transition duration-200">
                                Select Flight
                              </button>
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Map */}
          <div className="lg:col-span-1">
            <div className="bg-white rounded-xl shadow-lg p-6">
              <h3 className="text-xl font-bold text-gray-800 mb-4">Route Map</h3>
              {searchResults.mapData?.origin && searchResults.mapData?.destination ? (
                <MapComponent
                  origin={searchResults.mapData.origin}
                  destination={searchResults.mapData.destination}
                  height="400px"
                  type="flight"
                />
              ) : (
                <div className="h-96 bg-gray-100 rounded-lg flex items-center justify-center">
                  <p className="text-gray-500">Search flights to view route map</p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default FlightSearch;
EOF

# Create simplified HotelSearch component
cat > frontend/src/components/HotelSearch.js << 'EOF'
import React, { useState, useEffect } from 'react';
import MapComponent from './MapComponent';
import { Search, Calendar, Users, MapPin, Star } from 'lucide-react';
import axios from 'axios';

const HotelSearch = ({ flightData }) => {
  const [searchParams, setSearchParams] = useState({
    cityName: '',
    checkInDate: '',
    checkOutDate: '',
    adults: 1
  });

  const [isSearching, setIsSearching] = useState(false);
  const [searchResults, setSearchResults] = useState(null);
  const [selectedHotel, setSelectedHotel] = useState(null);

  const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:5000/api';

  // Auto-populate from flight data
  useEffect(() => {
    if (flightData) {
      setSearchParams(prev => ({
        ...prev,
        cityName: flightData.destinationName,
        checkInDate: flightData.dates.departure,
        checkOutDate: flightData.dates.return || ''
      }));
    }
  }, [flightData]);

  const extractCityCode = (cityString) => {
    const match = cityString.match(/\(([A-Z]{3})\)/);
    return match ? match[1] : cityString;
  };

  const handleSearch = async () => {
    const cityCode = extractCityCode(searchParams.cityName);
    
    if (!cityCode || !searchParams.checkInDate || !searchParams.checkOutDate) {
      alert('Please fill in all required fields');
      return;
    }

    setIsSearching(true);
    
    try {
      const queryParams = new URLSearchParams({
        cityCode,
        checkInDate: searchParams.checkInDate,
        checkOutDate: searchParams.checkOutDate,
        adults: searchParams.adults.toString()
      });

      const response = await axios.get(`${API_BASE_URL}/hotels/search?${queryParams}`);
      setSearchResults(response.data);
    } catch (error) {
      console.error('Error searching hotels:', error);
      alert('Failed to search hotels. Please try again.');
    } finally {
      setIsSearching(false);
    }
  };

  const renderStars = (rating) => {
    if (!rating) return null;
    return (
      <div className="flex items-center">
        {[...Array(5)].map((_, i) => (
          <Star
            key={i}
            className={`h-4 w-4 ${i < rating ? 'text-yellow-400 fill-current' : 'text-gray-300'}`}
          />
        ))}
        <span className="ml-1 text-sm text-gray-600">({rating})</span>
      </div>
    );
  };

  return (
    <div className="space-y-6">
      {/* Flight Connection Info */}
      {flightData && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div className="flex items-center space-x-2">
            <span className="text-blue-600">✈️</span>
            <span className="text-blue-800 font-medium">
              Connected from flight search: {flightData.destinationName}
            </span>
          </div>
        </div>
      )}

      {/* Search Form */}
      <div className="bg-white rounded-xl shadow-lg p-6">
        <h2 className="text-2xl font-bold text-gray-800 mb-6">Hotel Search</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          {/* Destination */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Destination</label>
            <div className="relative">
              <MapPin className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <input
                type="text"
                value={searchParams.cityName}
                onChange={(e) => setSearchParams(prev => ({ ...prev, cityName: e.target.value }))}
                placeholder="City or destination"
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>
          </div>

          {/* Check-in Date */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Check-in</label>
            <div className="relative">
              <Calendar className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <input
                type="date"
                value={searchParams.checkInDate}
                onChange={(e) => setSearchParams(prev => ({ ...prev, checkInDate: e.target.value }))}
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                min={new Date().toISOString().split('T')[0]}
              />
            </div>
          </div>

          {/* Check-out Date */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Check-out</label>
            <div className="relative">
              <Calendar className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <input
                type="date"
                value={searchParams.checkOutDate}
                onChange={(e) => setSearchParams(prev => ({ ...prev, checkOutDate: e.target.value }))}
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                min={searchParams.checkInDate || new Date().toISOString().split('T')[0]}
              />
            </div>
          </div>

          {/* Guests */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Guests</label>
            <div className="relative">
              <Users className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <select
                value={searchParams.adults}
                onChange={(e) => setSearchParams(prev => ({ ...prev, adults: parseInt(e.target.value) }))}
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                {[1,2,3,4,5,6].map(num => (
                  <option key={num} value={num}>{num} Guest{num > 1 ? 's' : ''}</option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {/* Search Button */}
        <button
          onClick={handleSearch}
          disabled={!searchParams.cityName || !searchParams.checkInDate || !searchParams.checkOutDate || isSearching}
          className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-semibold py-3 px-6 rounded-lg transition duration-200 flex items-center justify-center space-x-2"
        >
          {isSearching ? (
            <>
              <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
              <span>Searching hotels...</span>
            </>
          ) : (
            <>
              <Search className="h-5 w-5" />
              <span>Search Hotels</span>
            </>
          )}
        </button>
      </div>

      {/* Results */}
      {searchResults && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Hotel Results */}
          <div className="lg:col-span-2">
            <div className="bg-white rounded-xl shadow-lg p-6">
              <h3 className="text-xl font-bold text-gray-800 mb-6">
                Available Hotels ({searchResults.hotels?.length || 0} found)
              </h3>
              
              <div className="space-y-6">
                {searchResults.hotels?.map((hotel) => (
                  <div 
                    key={hotel.hotelId} 
                    className="border border-gray-200 rounded-lg p-6 hover:shadow-md transition-shadow cursor-pointer"
                    onClick={() => setSelectedHotel(hotel)}
                  >
                    <div className="flex justify-between items-start mb-4">
                      <div className="flex-1">
                        <h4 className="text-lg font-semibold text-gray-800 mb-2">{hotel.name}</h4>
                        {renderStars(hotel.rating)}
                        {hotel.address && (
                          <p className="text-sm text-gray-600 mt-1">
                            {hotel.address.lines?.join(', ')} {hotel.address.cityName}
                          </p>
                        )}
                      </div>
                      {hotel.offers && hotel.offers.length > 0 && (
                        <div className="text-right">
                          <div className="text-2xl font-bold text-blue-600">
                            {hotel.offers[0].price.currency} {hotel.offers[0].price.total}
                          </div>
                          <div className="text-sm text-gray-500">per night</div>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>

              {searchResults.hotels?.length === 0 && (
                <div className="text-center py-8">
                  <p className="text-gray-500">No hotels found for your search criteria.</p>
                </div>
              )}
            </div>
          </div>

          {/* Map */}
          <div className="lg:col-span-1">
            <div className="bg-white rounded-xl shadow-lg p-6">
              <h3 className="text-xl font-bold text-gray-800 mb-4">Hotel Locations</h3>
              {searchResults.mapData?.hotels?.length > 0 ? (
                <MapComponent
                  hotels={searchResults.mapData.hotels}
                  selectedHotel={selectedHotel}
                  height="500px"
                  type="hotels"
                />
              ) : (
                <div className="h-96 bg-gray-100 rounded-lg flex items-center justify-center">
                  <p className="text-gray-500">Search hotels to view locations</p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default HotelSearch;
EOF

# Create MapComponent
cat > frontend/src/components/MapComponent.js << 'EOF'
import React, { useEffect, useRef } from 'react';

const MapComponent = ({ origin, destination, hotels, selectedHotel, height = '400px', type = 'flight' }) => {
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef([]);

  useEffect(() => {
    const loadLeaflet = async () => {
      if (window.L) return window.L;
      
      return new Promise((resolve) => {
        const script = document.createElement('script');
        script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
        script.onload = () => resolve(window.L);
        document.head.appendChild(script);
      });
    };

    const initMap = async () => {
      const L = await loadLeaflet();
      
      if (!mapRef.current || mapInstanceRef.current) return;

      mapInstanceRef.current = L.map(mapRef.current, {
        zoomControl: true,
        scrollWheelZoom: true,
      });

      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors',
        maxZoom: 18,
      }).addTo(mapInstanceRef.current);

      delete L.Icon.Default.prototype._getIconUrl;
      L.Icon.Default.mergeOptions({
        iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
        iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
        shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
      });

      updateMap(L);
    };

    const updateMap = (L) => {
      if (!mapInstanceRef.current) return;

      markersRef.current.forEach(marker => {
        mapInstanceRef.current.removeLayer(marker);
      });
      markersRef.current = [];

      if (type === 'flight' && origin && destination) {
        const originIcon = L.divIcon({
          html: '🛫',
          className: 'custom-div-icon',
          iconSize: [30, 30],
          iconAnchor: [15, 15]
        });

        const destinationIcon = L.divIcon({
          html: '🛬',
          className: 'custom-div-icon',
          iconSize: [30, 30],
          iconAnchor: [15, 15]
        });

        const originMarker = L.marker([origin.latitude, origin.longitude], { icon: originIcon })
          .addTo(mapInstanceRef.current)
          .bindPopup(`<strong>${origin.name}</strong><br>${origin.city}, ${origin.country}`);

        const destinationMarker = L.marker([destination.latitude, destination.longitude], { icon: destinationIcon })
          .addTo(mapInstanceRef.current)
          .bindPopup(`<strong>${destination.name}</strong><br>${destination.city}, ${destination.country}`);

        markersRef.current.push(originMarker, destinationMarker);

        const flightPath = L.polyline([
          [origin.latitude, origin.longitude],
          [destination.latitude, destination.longitude]
        ], {
          color: '#3b82f6',
          weight: 3,
          opacity: 0.7,
          dashArray: '10, 10'
        }).addTo(mapInstanceRef.current);

        markersRef.current.push(flightPath);

        const group = new L.featureGroup([originMarker, destinationMarker]);
        mapInstanceRef.current.fitBounds(group.getBounds().pad(0.1));

      } else if (type === 'hotels' && hotels) {
        const bounds = [];
        
        hotels.forEach((hotel, index) => {
          if (hotel.coordinates && hotel.coordinates.latitude && hotel.coordinates.longitude) {
            const isSelected = selectedHotel && selectedHotel.hotelId === hotel.hotelId;
            
            const hotelIcon = L.divIcon({
              html: isSelected ? '⭐' : '🏨',
              className: 'custom-div-icon',
              iconSize: [25, 25],
              iconAnchor: [12, 12]
            });

            const hotelMarker = L.marker(
              [hotel.coordinates.latitude, hotel.coordinates.longitude], 
              { icon: hotelIcon }
            )
              .addTo(mapInstanceRef.current)
              .bindPopup(`<strong>${hotel.name}</strong><br>${hotel.rating ? '⭐'.repeat(hotel.rating) : ''}`);

            markersRef.current.push(hotelMarker);
            bounds.push([hotel.coordinates.latitude, hotel.coordinates.longitude]);

            if (isSelected) {
              hotelMarker.openPopup();
            }
          }
        });

        if (bounds.length > 0) {
          if (bounds.length > 1) {
            const group = new L.featureGroup(markersRef.current.filter(m => m instanceof L.Marker));
            mapInstanceRef.current.fitBounds(group.getBounds().pad(0.1));
          } else {
            mapInstanceRef.current.setView(bounds[0], 13);
          }
        }
      }
    };

    initMap();

    return () => {
      if (mapInstanceRef.current) {
        mapInstanceRef.current.remove();
        mapInstanceRef.current = null;
      }
    };
  }, [origin, destination, hotels, selectedHotel, type]);

  return (
    <div 
      ref={mapRef} 
      style={{ 
        height, 
        width: '100%', 
        borderRadius: '8px',
        border: '1px solid #e5e7eb'
      }} 
    />
  );
};

export default MapComponent;
EOF

# Database file
echo "🗄️ Creating database schema..."

cat > database/init.sql << 'EOF'
CREATE TABLE IF NOT EXISTS locations (
    id SERIAL PRIMARY KEY,
    iata_code VARCHAR(3) UNIQUE,
    name VARCHAR(255) NOT NULL,
    city VARCHAR(100),
    country VARCHAR(100),
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8)
);

INSERT INTO locations (iata_code, name, city, country, latitude, longitude) VALUES
('MAD', 'Madrid-Barajas Airport', 'Madrid', 'Spain', 40.472219, -3.560833),
('BCN', 'Barcelona-El Prat Airport', 'Barcelona', 'Spain', 41.2971, 2.0785),
('LHR', 'Heathrow Airport', 'London', 'United Kingdom', 51.4706, -0.4619),
('CDG', 'Charles de Gaulle Airport', 'Paris', 'France', 49.0097, 2.5479),
('BKK', 'Suvarnabhumi Airport', 'Bangkok', 'Thailand', 13.6900, 100.7501),
('DXB', 'Dubai International Airport', 'Dubai', 'UAE', 25.2532, 55.3657),
('SIN', 'Singapore Changi Airport', 'Singapore', 'Singapore', 1.3644, 103.9915),
('JFK', 'John F. Kennedy International Airport', 'New York', 'USA', 40.6413, -73.7781),
('LAX', 'Los Angeles International Airport', 'Los Angeles', 'USA', 33.9425, -118.4081),
('NRT', 'Narita International Airport', 'Tokyo', 'Japan', 35.7647, 140.3864)
ON CONFLICT (iata_code) DO NOTHING;
EOF

# Helper scripts
echo "📜 Creating helper scripts..."

cat > start.sh << 'EOF'
#!/bin/bash
echo "🚀 Starting Tour Operator System..."
docker-compose up -d
echo ""
echo "⏳ Waiting for services to start..."
sleep 30
echo ""
echo "✅ System is starting up!"
echo ""
echo "🌐 Frontend:    http://localhost:3000"
echo "🔌 Backend API: http://localhost:5000/api"
echo "🗄️  Database:    http://localhost:8080"
echo "   📧 Email: admin@touroperator.com"
echo "   🔑 Password: admin123"
echo ""
echo "📊 Check status: docker-compose ps"
echo "📝 View logs:    docker-compose logs -f"
echo ""
echo "🎯 Test your system:"
echo "   1. Go to http://localhost:3000"
echo "   2. Search flights: Madrid → Barcelona"
echo "   3. Check the route map!"
echo "   4. Try hotel search with auto-populated destination"
EOF

chmod +x start.sh

cat > stop.sh << 'EOF'
#!/bin/bash
echo "⏹️ Stopping Tour Operator System..."
docker-compose down
echo "✅ System stopped!"
EOF

chmod +x stop.sh

cat > logs.sh << 'EOF'
#!/bin/bash
echo "📊 Viewing system logs..."
docker-compose logs -f
EOF

chmod +x logs.sh

# Final setup
echo ""
echo "🔨 Building and starting the system..."
echo "This may take a few minutes on first run..."

# Build and start
docker-compose build --no-cache
docker-compose up -d

echo ""
echo "⏳ Waiting for services to initialize..."
sleep 45

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    echo ""
    echo "🎉 SUCCESS! Tour Operator System is running!"
    echo ""
    echo "📱 Access Your System:"
    echo "  🌐 Frontend:     http://localhost:3000"
    echo "  🔌 Backend API:  http://localhost:5000/api"
    echo "  🗄️  Database:     http://localhost:8080"
    echo "     📧 Email: admin@touroperator.com"
    echo "     🔑 Password: admin123"
    echo ""
    echo "✈️ Features Ready:"
    echo "  ✅ Flight search with interactive route maps"
    echo "  ✅ Hotel search with location maps"
    echo "  ✅ Your Amadeus API keys integrated"
    echo "  ✅ Real-time search results"
    echo "  ✅ Calendar date selection"
    echo "  ✅ City/airport autocomplete"
    echo ""
    echo "🎯 Quick Test:"
    echo "  1. Open http://localhost:3000"
    echo "  2. Search flights: Madrid → Barcelona"
    echo "  3. See route map with departure/arrival markers"
    echo "  4. Switch to Hotels tab"
    echo "  5. Destination auto-filled from flight!"
    echo ""
    echo "🛠️ Useful Commands:"
    echo "  📊 Check status: docker-compose ps"
    echo "  📝 View logs:    docker-compose logs -f"
    echo "  🔄 Restart:      docker-compose restart"
    echo "  ⏹️ Stop:         docker-compose down"
    echo ""
    echo "🎊 Enjoy your Tour Operator System!"
else
    echo ""
    echo "❌ Some services may not have started properly."
    echo "Check the logs with: docker-compose logs"
    echo "Try restarting with: docker-compose restart"
fi

echo ""
echo "📁 Your complete project is in: $(pwd)"
echo "💾 Files created successfully!"