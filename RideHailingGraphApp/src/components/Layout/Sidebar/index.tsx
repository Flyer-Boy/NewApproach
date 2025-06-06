import { Box, Flex, Stack } from "@chakra-ui/react";
import { CustomLayoutProps } from "@ride-hailing/@types/props";
import { useMemo } from "react";
import DriverProfileCard from "@ride-hailing/components/UserProfileCard/DriverProfileCard";
import PassengerProfileCard from "@ride-hailing/components/UserProfileCard/PassengerProfileCard";

const Sidebar = ({ element }: CustomLayoutProps) => {
  const userType = sessionStorage.getItem("userType");

  const profileComponent = useMemo(() => {
    if (userType) {
      switch (userType) {
        case "DRIVER":
          return <DriverProfileCard />;
        case "PASSENGER":
          return <PassengerProfileCard />;
      }
    }
  }, [userType]);
  return (
    <Flex gap={8}>
      <Stack w={"100%"} maxH={"90vh"} overflowY={"auto"}>
        <Box bg={"#fff"} borderRadius={"16px"}>
          {profileComponent}
        </Box>
        <Box>{element}</Box>
      </Stack>
    </Flex>
  );
};

export default Sidebar;
