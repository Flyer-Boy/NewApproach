import { HStack, VStack, Text, Image } from "@chakra-ui/react";
import { p_map_2 } from "@ride-hailing/assets/images";
import CustomSpinner from "@ride-hailing/components/Spinner";
import { useUserData } from "@ride-hailing/store";
import { useEffect, useState } from "react";
import { useReadCypher } from "use-neo4j";

const DriverSearching = () => {
  const [price, setPrice] = useState(0);
  const [time, setTime] = useState("");
  const [pickUp, setPickUp] = useState("");
  const [dropOff, setDropOff] = useState("");

  useEffect(() => {
    const interval = setInterval(() => {
      setTime((prevTime) => {
        const [hours, minutes, seconds] = prevTime.split(":").map(Number);
        const date = new Date();
        date.setHours(hours, minutes, seconds);
        date.setSeconds(date.getSeconds() + 1);
        const newTime = date.toTimeString().split(" ")[0];
        return newTime;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  const { bookingId } = useUserData();
    const get_booking_fare = `MATCH (pickUp:Address)<-[:HAS_ORIGIN]-(b:Booking {BookingID: $bookingId})-[:HAS_DESTINATION]->(dropOff:Address)
  RETURN b.Fare, apoc.temporal.format(duration.between(b.Date,datetime()),'HH:mm:ss') as TimeWaiting,
  pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName,
  dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName`;

  const { records, loading } = useReadCypher(get_booking_fare, {
    bookingId: bookingId,
  });

  useEffect(() => {
    if (Array.isArray(records) && records.length > 0) {
      setPrice(records[0]?.get("b.Fare"));
      setTime(records[0]?.get("TimeWaiting"));
      setPickUp(records[0]?.get("pickUpName"));
      setDropOff(records[0]?.get("dropOffName"));
    }
  }, [records]);

  return (
    <>
      <Image src={p_map_2} w={"100%"} />

      <VStack gap={"12px"} alignItems={"center"}>
        <HStack gap={0} ml={-8}>
          <CustomSpinner />
          <Text variant={"subtitle2"}>
            Waiting for drivers to pick your request...
           </Text>
        </HStack>

              <Text color="red" fontSize={18} variant={"subtitle2"}> Waiting Time: {time} </Text>

        <Text whiteSpace={"nowrap"}
                  color="gray.darkest"
                  fontWeight={600}
                  fontSize="sm"
                  variant={"subtitle2"}>{pickUp} → {dropOff}
        </Text>

        <HStack gap={12} alignItems={"flex-end"}>
          <VStack gap={2}>
            <Text variant={"subtitle2"} color={"gray.normal"}>
              Your ride fare:
            </Text>
            {loading ? (
              <CustomSpinner />
            ) : (
             <Text color={"#0A9726"} fontWeight={600} variant={"h3"}>$ {price}</Text>
            )}
          </VStack>
        </HStack>
      </VStack>
    </>
  );
};

export default DriverSearching;
