import { Center, Stack, Text } from "@chakra-ui/react";
import PassengerCard from "./PassengerCard";
import { useReadCypher } from "use-neo4j";
import CustomSpinner from "@ride-hailing/components/Spinner";

const PassengerList = () => {
    const query = `MATCH (ap:Passenger) WHERE NOT EXISTS {(ap)-[:HAS_ACTIVE_BOOKING]->(b:Booking)}
    RETURN "Available" as Status, ap.Name as Name, ap.Photo as Photo, ap.Phone as Phone, ap.Email as Email ORDER BY ap.Name
    UNION MATCH (bp:Passenger)-[:HAS_ACTIVE_BOOKING]->(b:Booking) 
    RETURN "Busy" as Status, bp.Name as Name, bp.Photo as Photo, bp.Phone as Phone, bp.Email as Email ORDER BY bp.Name;`;

  const { records, loading } = useReadCypher(query);

  return (
    <Stack bg={"#fff"} w={"100%"} h={"auto"} borderRadius={"16px"} p={6}>
          <Text fontSize={24} variant={"subtitle1"} fontWeight={700} mb={3}>
        Passenger List
      </Text>

      {loading ? (
        <Center h={"30vh"}>
          <CustomSpinner />
        </Center>
      ) : (
        <>
          {records?.length === 0 ? (
            <Center h={"200px"}>
              <Text>No Passenger available.</Text>
            </Center>
          ) : (
            <Stack gap={4} overflow={"auto"} maxH={"78vh"}>
              {records?.map((item, index) => {
                  
                  const passenger = {
                      Status: item.get("Status"),
                      Name: item.get("Name"),
                      Photo: item.get("Photo"),
                      Email: item.get("Email"),
                      Phone: item.get("Phone"),
                  };


                return <PassengerCard key={index} data={passenger} />;
              })}
            </Stack>
          )}
        </>
      )}
    </Stack>
  );
};

export default PassengerList;
