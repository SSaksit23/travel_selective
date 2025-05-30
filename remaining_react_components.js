// frontend/src/components/FlightSearch.js
import React, { useState } from 'react';
import MapComponent from './MapComponent';
import { Search, Calendar, Users, MapPin, Plane } from 'lucide-react';
import axios from 'axios';

const FlightSearch = ({ onFlightSelect }) => {
  const [searchParams, setSearchParams] = useState({
    origin: '',
    destination: '',
    departureDate: '',
    returnDate: '',
    tripType: 'roundtrip',
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

      if (searchParams.tripType === 'roundtrip' && searchParams.returnDate) {
        requestBody.returnDate = searchParams.returnDate;
      }

      const response = await axios.post(`${API_BASE_URL}/flights/search`, requestBody);
      setSearchResults(response.data);
      
      if (onFlightSelect) {
        onFlightSelect({
          destination: destinationCode,
          destinationName: searchParams.destination,
          dates: {
            departure: searchParams.departureDate,
            return: searchParams.returnDate
          }
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
        
        {/* Trip Type Toggle */}
        <div className="flex space-x-4 mb-6">
          <button
            onClick={() => setSearchParams(prev => ({ ...prev, tripType: 'roundtrip' }))}
            className={`px-4 py-2 rounded-lg font-medium ${
              searchParams.tripType === 'roundtrip'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            Round Trip
          </button>
          <button
            onClick={() => setSearchParams(prev => ({ ...prev, tripType: 'oneway' }))}
            className={`px-4 py-2 rounded-lg font-medium ${
              searchParams.tripType === 'oneway'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            One Way
          </button>
        </div>

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

          {/* Return Date */}
          {searchParams.tripType === 'roundtrip' && (
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Return</label>
              <div className="relative">
                <Calendar className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
                <input
                  type="date"
                  value={searchParams.returnDate}
                  onChange={(e) => setSearchParams(prev => ({ ...prev, returnDate: e.target.value }))}
                  className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  min={searchParams.departureDate || new Date().toISOString().split('T')[0]}
                />
              </div>
            </div>
          )}

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
                              <div className="text-sm text-gray-500">
                                {itinerary.segments.reduce((total, seg) => total + (seg.numberOfStops || 0), 0) === 0 
                                  ? 'Direct' 
                                  : `${itinerary.segments.length - 1} stop${itinerary.segments.length > 2 ? 's' : ''}`
                                }
                              </div>
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

// frontend/src/components/HotelSearch.js
import React, { useState, useEffect } from 'react';
import MapComponent from './MapComponent';
import { Search, Calendar, Users, MapPin, Star } from 'lucide-react';
import axios from 'axios';

const HotelSearch = ({ flightData }) => {
  const [searchParams, setSearchParams] = useState({
    cityCode: '',
    cityName: '',
    checkInDate: '',
    checkOutDate: '',
    adults: 1,
    rooms: 1
  });

  const [citySuggestions, setCitySuggestions] = useState([]);
  const [isSearching, setIsSearching] = useState(false);
  const [searchResults, setSearchResults] = useState(null);
  const [showCityDropdown, setShowCityDropdown] = useState(false);
  const [selectedHotel, setSelectedHotel] = useState(null);

  const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:5000/api';

  // Auto-populate from flight data
  useEffect(() => {
    if (flightData) {
      setSearchParams(prev => ({
        ...prev,
        cityCode: flightData.destination,
        cityName: flightData.destinationName,
        checkInDate: flightData.dates.departure,
        checkOutDate: flightData.dates.return || ''
      }));
    }
  }, [flightData]);

  const searchCities = async (query, setSuggestions) => {
    if (query.length < 2) {
      setSuggestions([]);
      return;
    }
    
    try {
      const response = await axios.get(`${API_BASE_URL}/locations/search?keyword=${encodeURIComponent(query)}`);
      const cities = response.data.filter(location => 
        location.type === 'CITY' || 
        (location.type === 'AIRPORT' && location.city)
      );
      setSuggestions(cities || []);
    } catch (error) {
      console.error('Error searching cities:', error);
      setSuggestions([]);
    }
  };

  const handleCitySearch = (e) => {
    const value = e.target.value;
    setSearchParams(prev => ({ ...prev, cityName: value }));
    searchCities(value, setCitySuggestions);
    setShowCityDropdown(true);
  };

  const selectCity = (location) => {
    setSearchParams(prev => ({ 
      ...prev, 
      cityCode: location.code,
      cityName: `${location.city || location.name} (${location.code})`
    }));
    setCitySuggestions([]);
    setShowCityDropdown(false);
  };

  const extractCityCode = (cityString) => {
    const match = cityString.match(/\(([A-Z]{3})\)/);
    return match ? match[1] : cityString;
  };

  const handleSearch = async () => {
    const cityCode = extractCityCode(searchParams.cityName) || searchParams.cityCode;
    
    if (!cityCode || !searchParams.checkInDate || !searchParams.checkOutDate) {
      alert('Please fill in all required fields');
      return;
    }

    if (new Date(searchParams.checkOutDate) <= new Date(searchParams.checkInDate)) {
      alert('Check-out date must be after check-in date');
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

  const handleHotelSelect = (hotel) => {
    setSelectedHotel(hotel);
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

  const formatDate = (dateString) => {
    if (!dateString) return '';
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', { 
      weekday: 'short', 
      month: 'short', 
      day: 'numeric' 
    });
  };

  const calculateNights = () => {
    if (!searchParams.checkInDate || !searchParams.checkOutDate) return 0;
    const checkIn = new Date(searchParams.checkInDate);
    const checkOut = new Date(searchParams.checkOutDate);
    const diffTime = Math.abs(checkOut - checkIn);
    return Math.ceil(diffTime / (1000 * 60 * 60 * 24));
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
        
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4 mb-6">
          {/* Destination */}
          <div className="relative lg:col-span-2">
            <label className="block text-sm font-medium text-gray-700 mb-2">Destination</label>
            <div className="relative">
              <MapPin className="absolute left-3 top-3 h-5 w-5 text-gray-400" />
              <input
                type="text"
                value={searchParams.cityName}
                onChange={handleCitySearch}
                placeholder="City or destination"
                className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              {showCityDropdown && citySuggestions.length > 0 && (
                <div className="absolute z-10 w-full mt-1 bg-white border border-gray-300 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                  {citySuggestions.map((location, index) => (
                    <button
                      key={index}
                      onClick={() => selectCity(location)}
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

        {/* Stay Duration Info */}
        {searchParams.checkInDate && searchParams.checkOutDate && (
          <div className="mb-4 p-3 bg-gray-50 rounded-lg">
            <div className="text-sm text-gray-600">
              {formatDate(searchParams.checkInDate)} → {formatDate(searchParams.checkOutDate)} 
              <span className="font-medium ml-2">({calculateNights()} night{calculateNights() !== 1 ? 's' : ''})</span>
            </div>
          </div>
        )}

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
                    className={`border rounded-lg p-6 hover:shadow-md transition-shadow cursor-pointer ${
                      selectedHotel?.hotelId === hotel.hotelId ? 'border-blue-500 bg-blue-50' : 'border-gray-200'
                    }`}
                    onClick={() => handleHotelSelect(hotel)}
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
                          <div className="text-xs text-gray-400">
                            Total: {hotel.offers[0].price.currency} {(parseFloat(hotel.offers[0].price.total) * calculateNights()).toFixed(2)}
                          </div>
                        </div>
                      )}
                    </div>

                    {/* Room Options */}
                    {hotel.offers && (
                      <div className="border-t pt-4">
                        <h5 className="font-medium text-gray-700 mb-2">Available Rooms:</h5>
                        <div className="space-y-2">
                          {hotel.offers.slice(0, 2).map((offer, index) => (
                            <div key={index} className="flex justify-between items-center p-2 bg-gray-50 rounded">
                              <div>
                                <div className="font-medium text-sm">
                                  {offer.room?.description?.text || 'Standard Room'}
                                </div>
                                <div className="text-xs text-gray-600">
                                  {offer.boardType || 'Room Only'}
                                </div>
                              </div>
                              <div className="text-right">
                                <div className="font-bold text-blue-600">
                                  {offer.price.currency} {offer.price.total}
                                </div>
                                <div className="text-xs text-gray-500">/night</div>
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>

              {searchResults.hotels?.length === 0 && (
                <div className="text-center py-8">
                  <p className="text-gray-500">No hotels found for your search criteria.</p>
                  <p className="text-sm text-gray-400 mt-2">Try adjusting your dates or destination.</p>
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

// frontend/src/components/MapComponent.js
import React, { useEffect, useRef } from 'react';

const MapComponent = ({ origin, destination, hotels, selectedHotel, height = '400px', type = 'flight' }) => {
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef([]);

  useEffect(() => {
    // Load Leaflet dynamically
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

      // Initialize map
      mapInstanceRef.current = L.map(mapRef.current, {
        zoomControl: true,
        scrollWheelZoom: true,
      });

      // Add OpenStreetMap tiles
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors',
        maxZoom: 18,
      }).addTo(mapInstanceRef.current);

      // Fix for marker icons
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

      // Clear existing markers
      markersRef.current.forEach(marker => {
        mapInstanceRef.current.removeLayer(marker);
      });
      markersRef.current = [];

      if (type === 'flight' && origin && destination) {
        // Flight route map
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

        // Add origin marker
        const originMarker = L.marker([origin.latitude, origin.longitude], { icon: originIcon })
          .addTo(mapInstanceRef.current)
          .bindPopup(`
            <div>
              <strong>${origin.name}</strong><br>
              ${origin.city}, ${origin.country}<br>
              <small>Origin (${origin.code})</small>
            </div>
          `);

        // Add destination marker
        const destinationMarker = L.marker([destination.latitude, destination.longitude], { icon: destinationIcon })
          .addTo(mapInstanceRef.current)
          .bindPopup(`
            <div>
              <strong>${destination.name}</strong><br>
              ${destination.city}, ${destination.country}<br>
              <small>Destination (${destination.code})</small>
            </div>
          `);

        markersRef.current.push(originMarker, destinationMarker);

        // Draw flight path
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

        // Fit map to show both points
        const group = new L.featureGroup([originMarker, destinationMarker]);
        mapInstanceRef.current.fitBounds(group.getBounds().pad(0.1));

      } else if (type === 'hotels' && hotels) {
        // Hotel locations map
        const bounds = [];
        
        hotels.forEach((hotel, index) => {
          if (hotel.coordinates && hotel.coordinates.latitude && hotel.coordinates.longitude) {
            const isSelected = selectedHotel && selectedHotel.hotelId === hotel.hotelId;
            
            const hotelIcon = L.divIcon({
              html: isSelected ? '⭐' : '🏨',
              className: `custom-div-icon ${isSelected ? 'selected-hotel' : ''}`,
              iconSize: [25, 25],
              iconAnchor: [12, 12]
            });

            const hotelMarker = L.marker(
              [hotel.coordinates.latitude, hotel.coordinates.longitude], 
              { icon: hotelIcon }
            )
              .addTo(mapInstanceRef.current)
              .bindPopup(`
                <div>
                  <strong>${hotel.name}</strong><br>
                  ${hotel.rating ? '⭐'.repeat(hotel.rating) + '<br>' : ''}
                  <small>Hotel ${index + 1}</small>
                </div>
              `);

            markersRef.current.push(hotelMarker);
            bounds.push([hotel.coordinates.latitude, hotel.coordinates.longitude]);

            // Open popup for selected hotel
            if (isSelected) {
              hotelMarker.openPopup();
            }
          }
        });

        // Fit map to show all hotels
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

    // Cleanup on unmount
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