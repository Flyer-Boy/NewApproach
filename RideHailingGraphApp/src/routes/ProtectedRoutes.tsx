import { CustomLayoutProps } from "@ride-hailing/@types/props";
import { Navigate } from "react-router-dom";
import { ROUTES } from "./routes.constant";
import Layout from "@ride-hailing/components/Layout";

const ProtectedRoutes = ({ element }: CustomLayoutProps) => {
  const userType = localStorage.getItem("userType");
  const userTypeId = localStorage.getItem("userTypeId");

  if (userType && userTypeId) {
    return <Navigate to={ROUTES.HOME} />;
  }
  return <Layout onlyNavbar={true}>{element}</Layout>;
};

export default ProtectedRoutes;
