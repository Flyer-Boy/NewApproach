import { CustomLayoutProps } from "@ride-hailing/@types/props";
import { Navigate } from "react-router-dom";
import { ROUTES } from "./routes.constant";
import Layout from "@ride-hailing/components/Layout";

const ProtectedRoutes = ({ element }: CustomLayoutProps) => {
  const userType = sessionStorage.getItem("userType");
  const isPassenger = userType === "PASSENGER";
  const userId = isPassenger ? sessionStorage.getItem("passengerId") : sessionStorage.getItem("driverId");

  if (userType && userId) {
    return <Navigate to={ROUTES.HOME} />;
  }
  return <Layout onlyNavbar={true}>{element}</Layout>;
};

export default ProtectedRoutes;
