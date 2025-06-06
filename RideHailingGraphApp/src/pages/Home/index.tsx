import PreviousList from "@ride-hailing/components/PreviousList";
import Passenger from "./Passenger";
import { Stack } from "@chakra-ui/react";
import Driver from "./Driver";
import { useMemo } from "react";

const Home = () => {
  const userType = sessionStorage.getItem("userType");

  const component = useMemo(() => {
    if (userType) {
      switch (userType) {
        case "DRIVER":
          return <Driver />;
        case "PASSENGER":
          return <Passenger />;
      }
    }
  }, [userType]);
  return (
    <Stack gap={5}>
      {component}
      <PreviousList />
    </Stack>
  );
};

export default Home;
