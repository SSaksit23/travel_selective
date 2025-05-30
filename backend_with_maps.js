// backend/server.js
const express = require('express');
const cors = require('cors');
const redis = require('redis');
const { Pool } = require('pg');
const Amadeus = require('amadeus');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 5000;

// Middleware
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:3000',
  credentials: true
}));
app.use(express.json());

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://tour_operator:secure_password@localhost:5432/tour_operator_db',
});

// Redis client for caching
const redisClient = redis.createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
  }
});

redisClient.on('error', (err) => {
  console.error('Redis Client Error:', err);
});

redisClient.on('connect', () => {
  console.log('Redis Client Connected');
});

// Connect to Redis
redisClient.connect();

// Amadeus client with your provided credentials
const amadeus = new Amadeus({
  clientId: process.env.AMADEUS_CLIENT_ID || 'Bd76Zxmr3DtsAgSCNVhRlgCzzFDROM07',
  clientSecret: process.env.AMADEUS_CLIENT_SECRET || 'Onw33473vAI1CTHS',
  hostname: process.env.AMADEUS_HOSTNAME || 'test' // 'test' for test environment
});

console.log('Amadeus client initialized with hostname:', process.env.AMADEUS_HOSTNAME || 'test');

// Utility functions
const getCachedData = async (key) => {
  try {
    const data = await redisClient.get(key);
    return data ? JSON.parse(data) : null;
  } catch (error) {
    console.error('Redis get error:', error);
    return null;
  }
};

const setCachedData = async (key, data, expiration = 900) => {
  try {
    await redisClient.setEx(key, expiration, JSON.stringify(data));
  } catch (error) {
    console.error('Redis set error:', error);
  }
};

// Get location coordinates from database
const getLocationCoordinates = async (iataCode) => {
  try {
    const result = await pool.query(
      'SELECT latitude, longitude, name, city, country FROM locations WHERE iata_code = $1',
      [iataCode.toUpperCase()]
    );
    return result.rows[0] || null;
  } catch (error) {
    console.error('Database error getting coordinates:', error);
    return null;
  }
};

// Save location coordinates to database
const saveLocationCoordinates = async (locationData) => {
  try {
    const { iataCode, name, city, country, countryCode, latitude, longitude, type } = locationData;
    await pool.query(`
      INSERT INTO locations (iata_code, name, city, country, country_code, latitude, longitude, type)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ON CONFLICT (iata_code) 
      DO UPDATE SET 
        name = EXCLUDED.name,
        city = EXCLUDED.city,
        country = EXCLUDED.country,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        updated_at = CURRENT_TIMESTAMP
    `, [iataCode, name, city, country, countryCode, latitude, longitude, type]);
  } catch (error) {
    console.error('Database error saving coordinates:', error);
  }
};

// ====================
// LOCATION & MAP ENDPOINTS
// ====================

// Search airports and cities with coordinates
app.get('/api/locations/search', async (req, res) => {
  try {
    const { keyword } = req.query;
    
    if (!keyword || keyword.length < 2) {
      return res.status(400).json({ error: 'Keyword must be at least 2 characters' });
    }

    const cacheKey = `locations_${keyword.toLowerCase()}`;
    const cachedResults = await getCachedData(cacheKey);
    
    if (cachedResults) {
      return res.json(cachedResults);
    }

    // Search Amadeus API
    const response = await amadeus.referenceData.locations.get({
      keyword,
      subType: 'AIRPORT,CITY',
      sort: 'analytics.travelers.score',
      'page[limit]': 20
    });

    const locations = await Promise.all(response.data.map(async (location) => {
      const locationData = {
        code: location.iataCode,
        name: location.name,
        city: location.address?.cityName,
        country: location.address?.countryName,
        countryCode: location.address?.countryCode,
        type: location.subType,
        relevance: location.analytics?.travelers?.score || 0,
        latitude: location.geoCode?.latitude,
        longitude: location.geoCode?.longitude
      };

      // Save to database if we have coordinates
      if (location.geoCode?.latitude && location.geoCode?.longitude && location.iataCode) {
        await saveLocationCoordinates({
          iataCode: location.iataCode,
          name: location.name,
          city: location.address?.cityName,
          country: location.address?.countryName,
          countryCode: location.address?.countryCode,
          latitude: location.geoCode.latitude,
          longitude: location.geoCode.longitude,
          type: location.subType.toLowerCase()
        });
      }

      return locationData;
    }));

    await setCachedData(cacheKey, locations, 86400); // Cache for 24 hours
    res.json(locations);

  } catch (error) {
    console.error('Location search error:', error);
    res.status(500).json({ 
      error: 'Failed to search locations',
      details: error.description || error.message 
    });
  }
});

// Get coordinates for a specific IATA code
app.get('/api/locations/:iataCode/coordinates', async (req, res) => {
  try {
    const { iataCode } = req.params;
    
    // First check database
    let coordinates = await getLocationCoordinates(iataCode);
    
    if (coordinates) {
      return res.json(coordinates);
    }

    // If not in database, search Amadeus API
    const response = await amadeus.referenceData.locations.get({
      keyword: iataCode,
      subType: 'AIRPORT,CITY'
    });

    const location = response.data.find(loc => loc.iataCode === iataCode.toUpperCase());
    
    if (!location || !location.geoCode) {
      return res.status(404).json({ error: 'Location coordinates not found' });
    }

    coordinates = {
      latitude: location.geoCode.latitude,
      longitude: location.geoCode.longitude,
      name: location.name,
      city: location.address?.cityName,
      country: location.address?.countryName
    };

    // Save to database for future use
    await saveLocationCoordinates({
      iataCode: location.iataCode,
      name: location.name,
      city: location.address?.cityName,
      country: location.address?.countryName,
      countryCode: location.address?.countryCode,
      latitude: location.geoCode.latitude,
      longitude: location.geoCode.longitude,
      type: location.subType.toLowerCase()
    });

    res.json(coordinates);

  } catch (error) {
    console.error('Coordinates error:', error);
    res.status(500).json({ 
      error: 'Failed to get coordinates',
      details: error.description || error.message 
    });
  }
});

// Get route map data (origin to destination)
app.get('/api/locations/route-map', async (req, res) => {
  try {
    const { origin, destination } = req.query;
    
    if (!origin || !destination) {
      return res.status(400).json({ error: 'Origin and destination are required' });
    }

    const [originCoords, destCoords] = await Promise.all([
      getLocationCoordinates(origin),
      getLocationCoordinates(destination)
    ]);

    if (!originCoords || !destCoords) {
      return res.status(404).json({ error: 'Could not find coordinates for one or both locations' });
    }

    res.json({
      origin: {
        code: origin.toUpperCase(),
        ...originCoords
      },
      destination: {
        code: destination.toUpperCase(),
        ...destCoords
      },
      route: {
        distance: calculateDistance(
          originCoords.latitude, originCoords.longitude,
          destCoords.latitude, destCoords.longitude
        )
      }
    });

  } catch (error) {
    console.error('Route map error:', error);
    res.status(500).json({ 
      error: 'Failed to get route map data',
      details: error.message 
    });
  }
});

// ====================
// FLIGHT SEARCH
// ====================

app.post('/api/flights/search', async (req, res) => {
  try {
    const {
      originLocationCode,
      destinationLocationCode,
      departureDate,
      returnDate,
      adults = 1,
      children = 0,
      infants = 0,
      travelClass = 'ECONOMY',
      nonStop = false,
      maxPrice,
      currencyCode = 'EUR'
    } = req.body;

    if (!originLocationCode || !destinationLocationCode || !departureDate) {
      return res.status(400).json({ 
        error: 'Origin, destination, and departure date are required' 
      });
    }

    const cacheKey = `flights_${originLocationCode}_${destinationLocationCode}_${departureDate}_${returnDate || 'oneway'}_${adults}_${travelClass}`;
    const cachedResults = await getCachedData(cacheKey);
    
    if (cachedResults) {
      return res.json({ ...cachedResults, cached: true });
    }

    const searchParams = {
      originLocationCode,
      destinationLocationCode,
      departureDate,
      adults: parseInt(adults),
      travelClass,
      currencyCode,
      max: 50
    };

    if (returnDate) searchParams.returnDate = returnDate;
    if (children > 0) searchParams.children = parseInt(children);
    if (infants > 0) searchParams.infants = parseInt(infants);
    if (nonStop) searchParams.nonStop = true;
    if (maxPrice) searchParams.maxPrice = parseFloat(maxPrice);

    console.log('Searching flights with params:', searchParams);

    const response = await amadeus.shopping.flightOffersSearch.get(searchParams);

    // Get coordinates for origin and destination
    const [originCoords, destCoords] = await Promise.all([
      getLocationCoordinates(originLocationCode),
      getLocationCoordinates(destinationLocationCode)
    ]);

    const flights = response.data.map(offer => ({
      id: offer.id,
      price: {
        total: offer.price.total,
        currency: offer.price.currency,
        base: offer.price.base,
        taxes: offer.price.taxes?.map(tax => ({
          amount: tax.amount,
          code: tax.code
        })) || []
      },
      itineraries: offer.itineraries.map(itinerary => ({
        duration: itinerary.duration,
        segments: itinerary.segments.map(segment => ({
          departure: {
            iataCode: segment.departure.iataCode,
            terminal: segment.departure.terminal,
            at: segment.departure.at
          },
          arrival: {
            iataCode: segment.arrival.iataCode,
            terminal: segment.arrival.terminal,
            at: segment.arrival.at
          },
          carrierCode: segment.carrierCode,
          number: segment.number,
          aircraft: segment.aircraft?.code,
          duration: segment.duration,
          numberOfStops: segment.numberOfStops || 0
        }))
      })),
      travelerPricings: offer.travelerPricings,
      validatingAirlineCodes: offer.validatingAirlineCodes,
      lastTicketingDate: offer.lastTicketingDate
    }));

    const result = {
      flights,
      meta: response.meta,
      searchParams,
      mapData: {
        origin: originCoords ? { code: originLocationCode, ...originCoords } : null,
        destination: destCoords ? { code: destinationLocationCode, ...destCoords } : null
      }
    };

    await setCachedData(cacheKey, result, 900);
    res.json(result);

  } catch (error) {
    console.error('Flight search error:', error);
    res.status(500).json({ 
      error: 'Failed to search flights',
      details: error.description || error.message 
    });
  }
});

// ====================
// HOTEL SEARCH
// ====================

app.get('/api/hotels/search', async (req, res) => {
  try {
    const {
      cityCode,
      checkInDate,
      checkOutDate,
      adults = 1,
      rooms = 1,
      currency = 'EUR'
    } = req.query;

    if (!cityCode || !checkInDate || !checkOutDate) {
      return res.status(400).json({ 
        error: 'City code, check-in and check-out dates are required' 
      });
    }

    const cacheKey = `hotels_${cityCode}_${checkInDate}_${checkOutDate}_${adults}_${rooms}`;
    const cachedResults = await getCachedData(cacheKey);
    
    if (cachedResults) {
      return res.json({ ...cachedResults, cached: true });
    }

    // First, get hotel list by city
    const hotelListResponse = await amadeus.referenceData.locations.hotels.byCity.get({
      cityCode
    });

    if (!hotelListResponse.data || hotelListResponse.data.length === 0) {
      return res.json({ hotels: [], message: 'No hotels found for this city' });
    }

    // Get hotel IDs (limit to first 50 for performance)
    const hotelIds = hotelListResponse.data.slice(0, 50).map(hotel => hotel.hotelId);

    // Search for hotel offers
    const offersResponse = await amadeus.shopping.hotelOffersSearch.get({
      hotelIds: hotelIds.join(','),
      checkInDate,
      checkOutDate,
      adults: parseInt(adults),
      roomQuantity: parseInt(rooms),
      currency,
      paymentPolicy: 'NONE',
      boardType: 'ROOM_ONLY'
    });

    // Get city coordinates
    const cityCoords = await getLocationCoordinates(cityCode);

    const hotels = offersResponse.data.map(hotel => ({
      hotelId: hotel.hotel.hotelId,
      name: hotel.hotel.name,
      rating: hotel.hotel.rating,
      contact: hotel.hotel.contact,
      address: hotel.hotel.address,
      description: hotel.hotel.description,
      amenities: hotel.hotel.amenities,
      media: hotel.hotel.media,
      geoCode: hotel.hotel.geoCode, // Hotel coordinates for map
      offers: hotel.offers?.map(offer => ({
        id: offer.id,
        checkInDate: offer.checkInDate,
        checkOutDate: offer.checkOutDate,
        roomQuantity: offer.roomQuantity,
        rateCode: offer.rateCode,
        rateFamilyEstimated: offer.rateFamilyEstimated,
        category: offer.category,
        description: offer.description,
        boardType: offer.boardType,
        room: offer.room,
        guests: offer.guests,
        price: offer.price,
        policies: offer.policies
      })) || []
    }));

    const result = {
      hotels: hotels.filter(hotel => hotel.offers && hotel.offers.length > 0),
      searchParams: { cityCode, checkInDate, checkOutDate, adults, rooms },
      mapData: {
        city: cityCoords ? { code: cityCode, ...cityCoords } : null,
        hotels: hotels.map(hotel => ({
          hotelId: hotel.hotelId,
          name: hotel.name,
          coordinates: hotel.geoCode,
          address: hotel.address,
          rating: hotel.rating
        })).filter(hotel => hotel.coordinates)
      }
    };

    await setCachedData(cacheKey, result, 3600);
    res.json(result);

  } catch (error) {
    console.error('Hotel search error:', error);
    res.status(500).json({ 
      error: 'Failed to search hotels',
      details: error.description || error.message 
    });
  }
});

// ====================
// UTILITY FUNCTIONS
// ====================

// Calculate distance between two coordinates (Haversine formula)
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return Math.round(R * c);
}

// ====================
// HEALTH CHECK & ERROR HANDLING
// ====================

app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    amadeus: 'Connected'
  });
});

// Error handling middleware
app.use((error, req, res, next) => {
  console.error('Unhandled error:', error);
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? error.message : 'Something went wrong'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully');
  await redisClient.quit();
  await pool.end();
  process.exit(0);
});

// Start server
app.listen(port, () => {
  console.log(`🚀 Server running on port ${port}`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`✈️  Amadeus API: ${process.env.AMADEUS_HOSTNAME || 'test'} environment`);
  console.log(`📍 CORS Origin: ${process.env.CORS_ORIGIN || 'http://localhost:3000'}`);
});

module.exports = app;