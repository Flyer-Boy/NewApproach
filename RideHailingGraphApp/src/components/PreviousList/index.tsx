import { Center, HStack, Stack, Text } from "@chakra-ui/react";
import Previouscard from "./PreviousCard";
import { useWriteCypher } from "use-neo4j";
import CustomSpinner from "../Spinner";
import { useEffect, useState } from "react";
import { useUserData } from "@ride-hailing/store";

const PreviousList = () => {
  const userType = sessionStorage.getItem("userType");
  const isPassenger = userType === "PASSENGER";
  const userId = isPassenger ? sessionStorage.getItem("passengerId") : sessionStorage.getItem("driverId");
  const { reload, setReload, setRideCount } = useUserData();

// Passenger query to get past ride details and Driver information
  const driver_query = `
MATCH (dr:Passenger {Phone: $id})-[:HAS_HISTORY]->(h:HistorY)-[:HAS]->(b:Booking)-[:HAS_CAR]->(c)-[:HAS_DRIVER]-(d), (pickUp:Address)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(dropOff:Address)
RETURN toString(b.Fare) as Fare, d.Name as Name, d.Photo as Photo, d.Phone as Phone, apoc.temporal.format(b.Date,'dd-MMM-YYYY HH:mm:ss') as Date,
pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName,
dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName ORDER BY b.Date DESC LIMIT 10

  `;

// Driver query to get past ride details and Passenger information
  const passenger_query = `
MATCH (dr:Driver {ID: $id})-[:HAS_HISTORY]->(h:HistorY)-[:HAS]->(b:Booking)-[:HAS_PASSENGER]->(p), (pickUp:Address)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(dropOff:Address)
RETURN toString(b.Fare) as Fare, p.Name as Name, p.Photo as Photo, p.Phone as Phone, apoc.temporal.format(b.Date,'dd-MMM-YYYY HH:mm:ss') as Date,
pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName,
dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName ORDER BY b.Date DESC LIMIT 10
    `;

  const { run: runDriver, loading } = useWriteCypher(driver_query);
  const { run: runPassenger, loading: isLoading } =
    useWriteCypher(passenger_query);

  const [records, setRecords] = useState<unknown>([]);

  const handleApiCall = async () => {
    try {
      const data = !isPassenger
        ? await runPassenger({ id: userId })
        : await runDriver({ id: userId });

      setRecords(data?.records);
      setRideCount(Array.isArray(data?.records) ? data?.records?.length : 0);
    } catch (e) {}
  };

  useEffect(() => {
    if (reload) {
      handleApiCall();
      setReload(false);
    }
  }, [reload]);

  // Check if records are available and map them to a suitable data structure
  const data = Array.isArray(records)
    ? records?.map((record) => ({
        photo: record.get("Photo"),
        name: record.get("Name"),
        phoneNumber: record.get("Phone"),
        pickUp: record.get("pickUpName"),
        dropOff: record.get("dropOffName"),
        fare: record.get("Fare"),
        date: record.get("Date"),
      }))
    : [];

  if (loading || isLoading) {
    return (
      <Center h={"100%"}>
        <CustomSpinner />
      </Center>
    );
  }

  return (
    <Stack bg={"#fff"} w={"100%"} h={"auto"} borderRadius={"16px"} p={6}>
      <HStack justifyContent={"space-between"} alignItems={"center"} gap={0}>
        <Text variant={"subtitle1"} fontWeight={700} mb={3}>
          Your past 10 rides
        </Text>
        {/* <Text
          variant={"subtitle2"}
          fontWeight={500}
          fontSize={"sm"}
          mb={3}
          onClick={() => navigate(`${ROUTES.PREVIOUS_BOOKING}`)}
          cursor={"pointer"}
        >
          See All
        </Text> */}
      </HStack>

      <Stack gap={3} overflowY={"auto"}>
        {data?.length === 0 && (
          <Center h={"300px"}>
            <Text>No previous rides.</Text>
          </Center>
        )}
        {data?.map((item, index) => <Previouscard key={index} data={item} />)}
      </Stack>
    </Stack>
  );
};

export default PreviousList;
