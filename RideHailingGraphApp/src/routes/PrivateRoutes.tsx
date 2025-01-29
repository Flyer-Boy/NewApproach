import { CustomLayoutProps } from "@ride-hailing/@types/props";
import { Navigate } from "react-router-dom";
import { ROUTES } from "./routes.constant";
import Layout from "@ride-hailing/components/Layout";

const PrivateRoutes = ({ element }: CustomLayoutProps) => {
  const userType = localStorage.getItem("userType");
  const userTypeId = localStorage.getItem("userTypeId");

  if (!userType || !userTypeId) {
    localStorage.clear();
    return <Navigate to={ROUTES.CHOOSE_USER} />;
  }
  return <Layout>{element}</Layout>;
};

export default PrivateRoutes;
