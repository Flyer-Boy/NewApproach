import { Button, Grid, GridItem, HStack, Image, Stack } from "@chakra-ui/react";
import { d_map_2 } from "@ride-hailing/assets/images";
import { PathComponent, RiderProfileCard } from "../Passenger/RiderFound";
import { AcceptIcon, DeclineIcon } from "@ride-hailing/assets/svg";
import FromTo from "@ride-hailing/components/FromToComponent";
import { useUserData } from "@ride-hailing/store";
import { useReadCypher, useWriteCypher } from "use-neo4j";

const StartRide = () => {
  const { setBookingId, setStage, bookingId } = useUserData();

  const driverId = sessionStorage.getItem("driverId");

  const query = `
OPTIONAL MATCH (b:Booking {BookingID: $bookingId })<-[r1:HAS]-(w:WaitinG)<-[:HAS]-()-[:HAS]->(a:ActivE),
(d:Driver {ID: $driverId})-[:HAS_CAR]->(c)<-[r2:HAS]-(:AvailablE)<-[:HAS]-()-[:HAS]->(u:BusY)
DELETE r1, r2
CREATE (a)-[:HAS]->(b),
       (c)-[r:HAS_ACTIVE_BOOKING]->(b),
       (b)-[t:HAS_CAR {Date: datetime()}]->(c),
       (u)-[:HAS]->(c);

`;

  const { run, loading } = useWriteCypher(query);

  const { records: passengerData } = useReadCypher(
    `MATCH (b:Booking {BookingID: $bookingId})<-[:HAS_ACTIVE_BOOKING]-(p:Passenger), (b)-[:HAS_ORIGIN]->(pickUp:Address), (b)-[:HAS_DESTINATION]->(dropOff:Address)
       RETURN p.Name, p.Phone, p.Photo, pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName,
       dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName, b.Fare`,
    { bookingId }
  );

  const passengerInfo = passengerData?.[0];

  const handleAccept = async () => {
    try {
      const result = await run({
        bookingId,
        driverId,
      });
      setStage(result?.records ? "RIDE_ACCEPTED" : "RIDE_REQUESTED");
    } catch (e) {}
  };

  return (
    <>
      <Image src={d_map_2} w={"100%"} />
      <Grid templateColumns={"repeat(7,1fr)"} gap={4}>
        <GridItem colSpan={5} as={Stack} gap={4}>
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
        <GridItem colSpan={2}>
          <PathComponent />
        </GridItem>

        <GridItem
          colSpan={7}
          color={"#0A9726"}
          fontSize={24}
          fontWeight={600}
          alignItems={"center"}
              >
          Fare: ${passengerInfo?.get("b.Fare")}
        </GridItem>
      </Grid>

      <HStack w={"100%"} gap={4}>
        <Button
          variant={"ghost"}
          w={"100%"}
          leftIcon={<DeclineIcon />}
          onClick={() => {
            setStage("INITIAL");
            setBookingId("");
          }}
        >
          Decline
        </Button>
        <Button
          w={"100%"}
          leftIcon={<AcceptIcon />}
          onClick={handleAccept}
          isLoading={loading}
        >
          Accept
        </Button>
      </HStack>
    </>
  );
};

export default StartRide;
