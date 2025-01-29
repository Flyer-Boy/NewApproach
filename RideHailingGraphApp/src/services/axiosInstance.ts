import axios from "axios";

const API = import.meta.env.VITE_APP_OPEN_CAGE_API;

const axiosInstance = axios.create({
  baseURL: API, // Base URL for the OpenCage API
  timeout: 5000, // Optional: Set a timeout for requests (5 seconds)
});

export default axiosInstance;
