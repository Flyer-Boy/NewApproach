import { CustomLayoutProps } from "@ride-hailing/@types/props";
import { Navigate } from "react-router-dom";
import { ROUTES } from "./routes.constant";
import Layout from "@ride-hailing/components/Layout";

const RestrictedRoutes = ({ element }: CustomLayoutProps) => {
  const userType = localStorage.getItem("userType");

  if (userType) {
    return <Navigate to={ROUTES.HOME} />;
  }
  return <Layout onlyNavbar={true}>{element}</Layout>;
};

export default RestrictedRoutes;
