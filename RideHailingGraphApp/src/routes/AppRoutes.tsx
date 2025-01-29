import { Suspense } from "react";
import { Navigate, useRoutes } from "react-router-dom";
import Home from "@ride-hailing/pages/Home";
import ChooseUser from "@ride-hailing/pages/ChooseUser";
import RestrictedRoutes from "./RestrictedRoutes";
import PrivateRoutes from "./PrivateRoutes";
import { ROUTES } from "./routes.constant";
import DriverList from "@ride-hailing/pages/DriverList";
import PassengerList from "@ride-hailing/pages/PassengerList";
import ProtectedRoutes from "./ProtectedRoutes";

const allRoutes = [
  {
    path: ROUTES.CHOOSE_USER,
    element: <RestrictedRoutes element={<ChooseUser />} />,
  },
  {
    path: ROUTES.DRIVER_LIST,
    element: <ProtectedRoutes element={<DriverList />} />,
  },
  {
    path: ROUTES.PASSENGER_LIST,
    element: <ProtectedRoutes element={<PassengerList />} />,
  },
  {
    path: ROUTES.HOME,
    element: <PrivateRoutes element={<Home />} />,
  },
  {
    path: ROUTES.ROOT,
    element: <Navigate to={ROUTES.HOME} replace={true} />,
  },
];

const AppRoutes = () => {
  const routes = useRoutes(allRoutes);
  return <Suspense>{routes}</Suspense>;
};
export default AppRoutes;
