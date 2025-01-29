import { Button, Grid, GridItem, Image, Stack, Text } from "@chakra-ui/react";
import { d_map_3 } from "@ride-hailing/assets/images";
import Timeline from "@ride-hailing/components/Timeline";
import { RiderProfileCard } from "../Passenger/RiderFound";
import FromTo from "@ride-hailing/components/FromToComponent";
import { CarIcon } from "@ride-hailing/assets/svg";
import { useUserData } from "@ride-hailing/store";
import { useReadCypher, useWriteCypher } from "use-neo4j";

const RideStarted = () => {
  const { bookingId, setStage } = useUserData();

  const { records: passengerData } = useReadCypher(
    `MATCH (b:Booking {BookingID: $bookingId})<-[:HAS_ACTIVE_BOOKING]-(p:Passenger), (b)-[:HAS_ORIGIN]->(pickUp:Address), (b)-[:HAS_DESTINATION]->(dropOff:Address) 
   RETURN p.Name, p.Phone, p.Photo, pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName,
   dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName, b.Fare`,
    { bookingId }
  );

  const startRideQuery = `MATCH (d:Driver)-[:HAS_CAR]->(c)-[:HAS_ACTIVE_BOOKING]->(b:Booking {BookingID: $bookingId }) CREATE (b)-[p:PICKED_UP {Date: datetime()}]->(c);`;

  const { run, loading } = useWriteCypher(startRideQuery);

  const handleRideStart = async () => {
    try {
      const result = await run({
        bookingId,
      });
      setStage(result?.records ? "RIDE_STARTED" : "RIDE_ACCEPTED");
    } catch (e) {}
  };

  const passengerInfo = passengerData?.[0];

  return (
    <>
      <Image src={d_map_3} w={"100%"} />
      <Grid templateColumns={"repeat(7,1fr)"}>
        <GridItem colSpan={3}>
          <Stack gap={4}>
            <Text variant={"subtitle1"} fontWeight={600} color={"gray.dark"}>
              Ride Status
            </Text>
            <Timeline />
          </Stack>
        </GridItem>
        <GridItem colSpan={4} as={Stack} gap={4} py={4}>
          <RiderProfileCard
            name={passengerInfo?.get("p.Name")}
            phoneNumber={passengerInfo?.get("p.Phone")}
            image={passengerInfo?.get("p.Photo")}
          />
          <FromTo
            from={passengerInfo?.get("pickUpName")}
            to={passengerInfo?.get("dropOffName")}
          />
        </GridItem>
      </Grid>
      <GridItem
        colSpan={7}
        color={"#0A9726"}
        fontSize={24}
        fontWeight={600}
        textAlign={"center"}
      >
        Fare: ${passengerInfo?.get("b.Fare")}
      </GridItem>

      <Button
        leftIcon={<CarIcon />}
        w={"100%"}
        onClick={handleRideStart}
        isLoading={loading}
      >
        Start Ride
      </Button>
    </>
  );
};

export default RideStarted;
