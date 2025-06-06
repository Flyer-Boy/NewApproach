import { Avatar, Box, Container, HStack } from "@chakra-ui/react";
import { BellIcon, HeroLogo, SettingIcon } from "@ride-hailing/assets/svg";
import { ROUTES } from "@ride-hailing/routes/routes.constant";
import { useUserData } from "@ride-hailing/store";
import { useNavigate } from "react-router-dom";
import { useReadCypher } from "use-neo4j";

const Navbar = () => {
  const navigate = useNavigate();
  const userType = sessionStorage.getItem("userType");
  const isPassenger = userType === "PASSENGER";
  const userId = isPassenger ? sessionStorage.getItem("passengerId") : sessionStorage.getItem("driverId");
  const driverquery = `MATCH (d:Driver {id: $id}) RETURN d`;
  const passengerQuery = `MATCH (d:Passenger {Phone: $id}) RETURN d`;

  const { setBookingId } = useUserData();

  const query = isPassenger ? passengerQuery : driverquery;
  const { records } = useReadCypher(query, { id: userId });
  const data = records?.[0]?.get("d")?.properties;
  return (
    <Box py={"20px"} bg={"primary.800"}>
      <Container maxW={{ base: "100%", xl: "75%" }}>
        <HStack w={"100%"} justifyContent={"space-between"}>
          <Box
            sx={{ svg: { path: { fill: "#fff" } } }}
            cursor={"pointer"}
            onClick={() => navigate(ROUTES.HOME)}
          >
            <HeroLogo />
          </Box>

          <HStack gap={4}>
            <Box
              cursor={"pointer"}
              onClick={() => {
                sessionStorage.clear();
                navigate(ROUTES.CHOOSE_USER);
                setBookingId("");
              }}
            >
              <SettingIcon />
            </Box>
            <BellIcon />
            {data && (
              <Avatar
                src={data?.image}
                name={data?.name}
                bg={"#fff"}
                color={"#000"}
                size={"sm"}
              />
            )}
          </HStack>
        </HStack>
      </Container>
    </Box>
  );
};

export default Navbar;
