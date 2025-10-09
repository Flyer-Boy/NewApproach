import { Box, Center, Image, Text } from "@chakra-ui/react";
import { d_map_2 } from "@ride-hailing/assets/images";
import Previouscard from "@ride-hailing/components/PreviousList/PreviousCard";
import { useUserData } from "@ride-hailing/store";
import { useEffect, useState } from "react";
import { useWriteCypher } from "use-neo4j";

const IdealState = () => {
const query = `MATCH (p:Passenger)-[:HAS_ACTIVE_BOOKING]->(b:Booking)<-[:HAS]-(w:WaitinG),
(pickUp:Address)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(dropOff:Address)
RETURN p.Name, p.Phone, p.Photo, b.BookingID, b.Fare,
pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP as pickUpName,
dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP as dropOffName,
CASE 
  WHEN b.Date IS NOT NULL 
  THEN apoc.temporal.format(duration.between(b.Date, datetime()), 'HH:mm:ss') 
  ELSE null 
END as Date
ORDER BY b.Date
`;

  const [refetchCount, setRefetchCount] = useState(0);

  const { run } = useWriteCypher(query);

  const [records, setRecords] = useState<unknown>([]);

  const handleApiCall = async () => {
    try {
      const status = await run();
      setRefetchCount((prev) => prev++);

      setRecords(status?.records);
    } catch (e) {}
  };

  useEffect(() => {
    const status = setInterval(() => handleApiCall(), 3000);

    return () => clearInterval(status);
  }, [refetchCount]);

  const { setStage, setBookingId } = useUserData();

  return (
    <>
      <Image src={d_map_2} w={"100%"} />
      <Text variant={"subtitle1"} fontWeight={600} color={"gray.dark"}>
        Ride requests waiting...
      </Text>
      {
        <>
          {Array.isArray(records) && records?.length === 0 ? (
            <Center h={"300px"}>
              <Text>No ride requests available.</Text>
            </Center>
          ) : (
            <>
              {Array.isArray(records) &&
                records?.map((item, index) => {
                  const rideRequest = {
                    bookingId: item.get("b.BookingID"),
                    pickUp: item.get("pickUpName"),
                    dropOff: item.get("dropOffName"),
                    name: item.get("p.Name"),
                    phoneNumber: item.get("p.Phone"),
                    photo: item.get("p.Photo"),
                    fare: item.get("b.Fare"),
                    date: item.get("Date"),
                  };

                  return (
                    <Box
                      key={index}
                      cursor={"pointer"}
                      onClick={() => {
                        setBookingId(rideRequest.bookingId);
                        setStage("RIDE_REQUESTED");
                      }}
                    >
                      <Previouscard data={rideRequest} />
                    </Box>
                  );
                })}
            </>
          )}
        </>
      }
    </>
  );
};

export default IdealState;


