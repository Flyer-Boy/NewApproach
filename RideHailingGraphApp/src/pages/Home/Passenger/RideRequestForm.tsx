import { FormProvider, useForm } from "react-hook-form";
import { Button, Image, Stack, Text } from "@chakra-ui/react";
import { LocationIcon, SearchIcon } from "@ride-hailing/assets/svg";
import FormControl from "@ride-hailing/components/Form/FormControl";
import { RideRequestSchemaType } from "@ride-hailing/@types/rideRequest";
import { yupResolver } from "@hookform/resolvers/yup";
import { rideRequestSchema } from "@ride-hailing/schema/rideRequest";
import { p_map_1 } from "@ride-hailing/assets/images";
import { useReadCypher, useWriteCypher } from "use-neo4j";
import { useUserData } from "@ride-hailing/store";
import { useEffect, useState } from "react";

const RideRequestForm = () => {
  const passengerId = sessionStorage.getItem("passengerId");

  // Get the prefered payment method 
  const get_prefered_payment_methods = `MATCH (:Passenger {Phone: $passengerId})-[:HAS_PREFERED_PAYMENT]->(pm:PaymentMethod) RETURN   pm.Type+", "+ pm.Issuer + ", ending in " + right(toString(pm.CardNumber),4) as paymentString, pm.CardNumber;`;

  const { records: prefered_payment, loading: paymentLoading } = useReadCypher(
    get_prefered_payment_methods,
    { passengerId },
  );

  const methods = useForm({
    resolver: yupResolver(rideRequestSchema),
  });

  useEffect(() => {
    if (!paymentLoading) {
      if (Array.isArray(prefered_payment) && prefered_payment.length > 0) {
        methods.setValue(
          `paymentMethod`,
          prefered_payment[0].get("paymentString"),
        );
      } else {
        methods.setValue("paymentMethod", "Cash");
      }
    }
  }, [prefered_payment, paymentLoading]);

  const { setStage, setBookingId } = useUserData();

  // Get the fare
const { records: fareData } = useReadCypher(`OPTIONAL MATCH (c:Car)<-[:HAS]-(:AvailablE)
CALL () {MATCH (b:Booking)<-[:HAS]-(:WaitinG) RETURN toFloat(count(b)) AS Bookings_Waiting}
WITH Bookings_Waiting, toFloat(count (c)+0.5) as Cars_Available RETURN round(toFloat(Bookings_Waiting/(Cars_Available))*ceil(rand()*25)+15,2) as Fare;
`);

  const [fare, setFare] = useState(11);

  useEffect(() => {
    if (Array.isArray(fareData) && fareData.length > 0) {
      setFare(fareData?.[0]?.get("Fare"));
    }
  }, [fareData]);

  //Create the Booking!
  const { run, loading } = useWriteCypher(
    `OPTIONAL MATCH  (p:Passenger {Phone: $passengerId })-[:HAS_PREFERED_PAYMENT]->(pm ), (w:WaitinG {Name: "WaitinG"}),
(pickUp:Address {GeoHash: $pickUpId})<-[:HAS]-(:AddresseS)-[:HAS]->(dropOff:Address {GeoHash: $dropOffId})
CREATE (b:Booking {BookingID: "B"+left(randomUUID(),8)+right(randomUUID(),4), Date: localdatetime.transaction(), Fare: $fare })-[:HAS_PASSENGER]->(p),
       (b)-[:HAS_PAYMENT]->(pm),
         (b)-[:HAS_ORIGIN]->(pickUp),
       (b)-[:HAS_DESTINATION]->(dropOff),
       (p)-[:HAS_ACTIVE_BOOKING]->(b),
       (w)-[:HAS]->(b)
RETURN b.BookingID;
`,
  );

  // Get existing Addresses for the user to select from
  const address_query = `MATCH (n:Address) RETURN n.GeoHash, n.StreetNum + " " + n.StreetName + ", " + n.City + ", " + n.State + ", " + n.ZIP  as Address;`;

  const { records } = useReadCypher(address_query);

  const options = records?.map((item) => ({
    id: item?.get("n.GeoHash"),
    Address: item?.get("Address"),
  }));

  const handleExplore = async (data: RideRequestSchemaType) => {
    const { pickUpId, dropOffId } = data;

    try {
      const result = await run({
        passengerId,
        pickUpId,
        dropOffId,
        fare: fare.toFixed(2),
      });

      setBookingId(result?.records?.[0].get("b.BookingID"));
      setStage("RIDE_REQUESTED");
    } catch (e) {}
  };

  return (
    <>
      <Image src={p_map_1} w={"100%"} />
      <FormProvider {...methods}>
        <form onSubmit={methods.handleSubmit(handleExplore)}>
          <Stack gap={4}>
            <FormControl
              inputControl="select"
              name="pickUpId"
              label="Pick Up"
              options={options}
              inputRightElement={<Text fontSize={20}>📍</Text>}
            />
            <FormControl
              inputControl="select"
              name="dropOffId"
              label="Drop-Off"
              placeholder="Where to go?"
              options={options}
              inputRightElement={<LocationIcon />}
            />
            <FormControl
              inputControl="input"
              name="paymentMethod"
              label="Payment Method"
              isReadOnly
            />
            <Button type="submit" leftIcon={<SearchIcon />} isLoading={loading}>
              Explore/Book
            </Button>
          </Stack>
        </form>
      </FormProvider>
    </>
  );
};

export default RideRequestForm;
