import { Center, Stack, Text } from "@chakra-ui/react";
import DriverCard from "./DriverCard";
import { useReadCypher } from "use-neo4j";
import CustomSpinner from "@ride-hailing/components/Spinner";

const DriverList = () => {
  const query = `MATCH (ad:Driver)-[:HAS_CAR]->(n:Car)<-[:HAS]-(:AvailablE) 
    RETURN "Available" as Status, ad.Name as Name, ad.License as License, ad.ID as ID, ad.Photo as Photo, ad.Phone as Phone, ad.Email as Email, n.Plate as Plate, n.Make as Make, n.Model as Model, n.Color as Color, n.Capacity as Capacity ORDER BY ad.Name
    UNION MATCH (bd:Driver)-[:HAS_CAR]->(n:Car)<-[:HAS]-(b:BusY)
    RETURN "Busy" as Status, bd.Name as Name, bd.License as License, bd.ID as ID, bd.Photo as Photo, bd.Phone as Phone, bd.Email as Email, n.Plate as Plate, n.Make as Make, n.Model as Model, n.Color as Color, n.Capacity as Capacity ORDER BY bd.Name;`;

  const { records, loading } = useReadCypher(query);

  return (
    <Stack
      bg={"#fff"}
      w={"100%"}
      h={"auto"}
      borderRadius={"16px"}
      p={6}
      gap={4}
    >
          <Text fontSize={24} variant={"subtitle1"} fontWeight={700}>
        Driver List
      </Text>
      {loading ? (
        <Center h={"30vh"}>
          <CustomSpinner />
        </Center>
      ) : (
        <>
          {records?.length === 0 ? (
            <Center h={"200px"}>
              <Text>No Driver Available.</Text>
            </Center>
          ) : (
            <Stack gap={4} overflow={"auto"} maxH={"78vh"}>
              {records?.map((item, index) => {
                const driver = {
                  Status: item.get("Status"),
                  ID: item.get("ID"),
                  Name: item.get("Name"),
                  License: item.get("License"),
                  Photo: item.get("Photo"),
                  Email: item.get("Email"),
                  Phone: item.get("Phone"),
                  Plate: item.get("Plate"),
                  Make: item.get("Make"),
                  Model: item.get("Model"),
                  Color: item.get("Color"),
                  Capacity: item.get("Capacity"),
                };

                return <DriverCard key={index} data={driver} />;
              })}
            </Stack>
          )}
        </>
      )}
    </Stack>
  );
};

export default DriverList;
