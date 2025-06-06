import { CustomLayoutProps } from "@ride-hailing/@types/props";
import { Navigate } from "react-router-dom";
import { ROUTES } from "./routes.constant";
import Layout from "@ride-hailing/components/Layout";

const PrivateRoutes = ({ element }: CustomLayoutProps) => {
  const userType = sessionStorage.getItem("userType");
  const isPassenger = userType === "PASSENGER";
  const userId = isPassenger ? sessionStorage.getItem("passengerId") : sessionStorage.getItem("driverId");

  if (!userType || !userId) {
    sessionStorage.clear();
    return <Navigate to={ROUTES.CHOOSE_USER} />;
  }
  return <Layout>{element}</Layout>;
};

export default PrivateRoutes;
