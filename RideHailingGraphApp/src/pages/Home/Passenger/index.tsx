import { HStack, Stack, Text } from "@chakra-ui/react";
import { TimeIcon } from "@ride-hailing/assets/svg";
import useCurrentTime from "@ride-hailing/hooks/useCurrentTime";
import { useEffect, useMemo, useState } from "react";
import DriverSearching from "./DriverSearching";
import RideRequestForm from "./RideRequestForm";
import RiderFound from "./RiderFound";
import RideCompleted from "./RideCompleted";
import { useWriteCypher } from "use-neo4j";
import { useUserData } from "@ride-hailing/store";

const Passenger = () => {
  const currentTime = useCurrentTime();
  const passengerId = sessionStorage.getItem("passengerId");

  const { stage, setBookingId, setStage, bookingId } = useUserData();

  const statusQuery = `OPTIONAL MATCH (p:Passenger {Phone: $passengerId })-[:HAS_ACTIVE_BOOKING]->(b:Booking)
  OPTIONAL MATCH (b)<-[:HAS]-(a:ActivE)
  OPTIONAL MATCH (b)<-[:HAS]->(w:WaitinG)
  RETURN b.BookingID, COALESCE( a.Name, w.Name, "Free") AS stateName`;

  const { run } = useWriteCypher(statusQuery);

  const [refetchCount, setRefetchCount] = useState(0);

  const handleApiCall = async () => {
    try {
      const status = await run({ passengerId });

      setRefetchCount((prev) => prev++);
      const stage = status?.records?.[0]?.get("stateName");
      const bookingId = status?.records?.[0]?.get("b.BookingID");
      console.log(stage, bookingId);
      setBookingId(bookingId);
      setStage(
        stage === "WaitinG"
          ? "RIDE_REQUESTED"
          : stage === "ActivE"
            ? "RIDE_STARTED"
            : "INITIAL"
      );
    } catch (e) {}
  };

  useEffect(() => {
    handleApiCall();
  }, []);

  useEffect(() => {
    if (bookingId !== "") {
      const status = setInterval(() => handleApiCall(), 3000);

      return () => clearInterval(status);
    }
  }, [refetchCount, bookingId]);

  const component = useMemo(() => {
    if (stage) {
      switch (stage) {
        case "INITIAL":
          return <RideRequestForm />;
        case "RIDE_REQUESTED":
          return <DriverSearching />;
        case "RIDER_FOUND":
          return <RiderFound />;
        case "RIDE_ACCEPTED":
          return <RiderFound />;
        case "RIDE_STARTED":
          return <RiderFound />;
        case "RIDE_COMPLETED":
          return <RideCompleted />;
      }
    }
  }, [stage]);
  return (
    <Stack bg={"white"} minH={"646px"} p={6} borderRadius={"16px"} gap={6}>
      <HStack justifyContent={"space-between"}>
        <Text variant={"subtitle2"} fontWeight={700}>
          Current Rides
        </Text>
        <HStack>
          <TimeIcon />
          <Text variant={"subtitle2"} color={"primary.500"}>
            {currentTime}
          </Text>
        </HStack>
      </HStack>

      {component}
    </Stack>
  );
};

export default Passenger;
