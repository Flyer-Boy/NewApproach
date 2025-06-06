import { HStack, Stack, Text } from "@chakra-ui/react";
import { TimeIcon } from "@ride-hailing/assets/svg";
import useCurrentTime from "@ride-hailing/hooks/useCurrentTime";
import { useEffect, useMemo } from "react";
import IdealState from "./IdealState";
import StartRide from "./StartRide";
import CompleteRide from "./CompleteRide";
import RideSuccess from "./RideSuccess";
import { useUserData } from "@ride-hailing/store";
import { useReadCypher, useWriteCypher } from "use-neo4j";
import RideStarted from "./RideStarted";

const Driver = () => {
  const currentTime = useCurrentTime();

  const { stage, setStage, setBookingId, bookingId } = useUserData();

  const driverId = sessionStorage.getItem("driverId");

  const statusQuery = `MATCH (d:Driver {ID: $driverId})-[:HAS_CAR]->(c:Car),(c)-[:HAS_ACTIVE_BOOKING]->(b:Booking) RETURN b.BookingID`;

  const { records } = useReadCypher(statusQuery, { driverId });

  const { run } = useWriteCypher(
    `MATCH (b:Booking {BookingID: $bookingId})-[:PICKED_UP]->(c) RETURN c`
  );

  useEffect(() => {
    if (Array.isArray(records) && records?.length !== 0) {
      setStage("RIDE_ACCEPTED");
      setBookingId(records?.[0]?.get("b.BookingID"));
    } else {
      setStage("INITIAL");
    }
  }, [records]);

  const handleBookingStatus = async () => {
    const result = await run({
      bookingId,
    });

    setStage(result?.records.length !== 0 ? "RIDE_STARTED" : "RIDE_ACCEPTED");
  };

  useEffect(() => {
    if (bookingId && stage !== "RIDE_REQUESTED") {
      handleBookingStatus();
    }
  }, [bookingId]);

  const component = useMemo(() => {
    if (stage) {
      switch (stage) {
        case "INITIAL":
          return <IdealState />;
        case "RIDE_REQUESTED":
          return <StartRide />;
        case "RIDE_ACCEPTED":
          return <RideStarted />;
        case "RIDE_STARTED":
          return <CompleteRide />;
        case "RIDE_COMPLETED":
          return <RideSuccess />;
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

export default Driver;
