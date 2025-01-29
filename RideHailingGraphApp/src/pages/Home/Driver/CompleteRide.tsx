import { Button, Grid, GridItem, Image, Stack, Text } from "@chakra-ui/react";
import { d_map_4 } from "@ride-hailing/assets/images";
import Timeline from "@ride-hailing/components/Timeline";
import { RiderProfileCard } from "../Passenger/RiderFound";
import FromTo from "@ride-hailing/components/FromToComponent";
import { CarIcon } from "@ride-hailing/assets/svg";
import { useReadCypher, useWriteCypher } from "use-neo4j";
import { useUserData } from "@ride-hailing/store";

const CompleteRide = () => {
  const { bookingId, setStage } = useUserData();

  const { records: passengerData } = useReadCypher(
      `MATCH (b:Booking {BookingID: $bookingId})<-[:HAS_ACTIVE_BOOKING]-(p:Passenger), (b)-[:HAS_ORIGIN]->(pickUp:Address), (b)-[:HAS_DESTINATION]->(dropOff:Address) 
       RETURN p.Name, p.Phone, p.Photo, pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName,
       dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName, b.Fare`,
    { bookingId },
  );

  const userTypeId = localStorage.getItem("userTypeId");

  const passengerInfo = passengerData?.[0];

  const { run, loading } = useWriteCypher(
    `OPTIONAL MATCH (dh:HistorY)<-[:HAS_HISTORY]-(d:Driver {ID: $userTypeId })-[:HAS_CAR]->(c)-[r1:HAS_ACTIVE_BOOKING]->(b)<-[r3:HAS]-(:ActivE)<-[:HAS]-(:BookingS)-[:HAS]->(t:PasT), 
                (a:AvailablE)<-[:HAS]-(:FleeT)-[:HAS]->(u:BusY)-[r2:HAS]->(c),(ph:HistorY)<-[:HAS_HISTORY]-(p:Passenger)-[r4:HAS_ACTIVE_BOOKING]->(b)
CREATE (t)-[:HAS {Date: datetime()}]->(b), 
      (a)-[:HAS]->(c), 
      (dh)-[:HAS {Date: datetime()}]->(b),
      (b)<-[:HAS {Date: datetime()}]-(ph) 
DELETE r1, r2, r3, r4 RETURN b;
`,
  );

  const handleRideCompleted = async () => {
    try {
      const result = await run({
        userTypeId,
      });
      setStage(
        Array.isArray(result?.records) && result?.records?.length > 0
          ? "RIDE_COMPLETED"
          : "RIDE_STARTED",
      );
    } catch (e) {}
  };
  return (
    <>
      <Image src={d_map_4} w={"100%"} />
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
      <Stack gap={0} flex={1} textAlign={"center"}>
        <Text color={"#0A9726"} fontWeight={600} fontSize={24} >Fare: ${passengerInfo?.get("b.Fare")}</Text> 
      </Stack>
      <Button
        leftIcon={<CarIcon />}
        w={"100%"}
        isLoading={loading}
        onClick={handleRideCompleted}
      >
        Ride Completed
      </Button>
    </>
  );
};

export default CompleteRide;
