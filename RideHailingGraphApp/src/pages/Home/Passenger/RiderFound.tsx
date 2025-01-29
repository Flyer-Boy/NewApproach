import {
  Avatar,
  Grid,
  GridItem,
  HStack,
  Image,
  Stack,
  Text,
} from "@chakra-ui/react";
import { driverLocation, p_map_2 } from "@ride-hailing/assets/images";
import { ProfileTickBoldIcon, VehicleIcon } from "@ride-hailing/assets/svg";
import { useUserData } from "@ride-hailing/store";
import { useMemo } from "react";
import { useReadCypher } from "use-neo4j";

export const PathComponent = () => {
  return (
    <Stack
      bgColor={"gray.lightest"}
      w={"204px"}
      h={"252px"}
      borderRadius={"12px"}
      gap={4}
    >
      <Image src={driverLocation} w={"full"} h={"75%"} />
      <HStack justifyContent={"space-evenly"} gap={2}>
        <Text
          variant={"subtitle2"}
          px={"8px"}
          py={"6px"}
          border={"1px solid #E0E0E0"}
          borderRadius={"23px"}
        >
          0.2 km away
        </Text>
        <Text
          variant={"subtitle2"}
          px={"8px"}
          py={"6px"}
          border={"1px solid #E0E0E0"}
          borderRadius={"23px"}
        >
          2 min
        </Text>
      </HStack>
    </Stack>
  );
};

export const RiderProfileCard = ({
  name,
  phoneNumber,
  image,
}: {
  name: string;
  phoneNumber: string;
  image: string;
}) => {
  return (
    <HStack
      justifyContent={"space-between"}
      border={"1px solid #ebebeb"}
      borderRadius={"2xl"}
      p={4}
      w={"100%"}
    >
      <HStack>
        <Avatar src={image} size={"lg"} border={"2px solid black"} />
        <Stack gap={0}>
          <Text variant={"subtitle1"} whiteSpace={"nowrap"}>
            {name}
          </Text>
          <Text variant={"pRegular"} color={"gray.dark"}>
            Ph: {phoneNumber}
          </Text>
        </Stack>
      </HStack>
    </HStack>
  );
};

const RiderFound = () => {
  const { bookingId } = useUserData();

  const { records: driverData } = useReadCypher(
    `MATCH (b:Booking{BookingID: $bookingId})-[:HAS_CAR]->(c:Car),(c)-[:HAS_DRIVER]->(d:Driver), (b)-[:HAS_ORIGIN]->(pickUp:Address),
     (b)-[:HAS_DESTINATION]->(dropOff:Address)
     RETURN d.Name, d.Phone, d.Photo, b.BookingID, b.Fare,
     pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName, 
     dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName, c.Plate, c.Color, c.Capacity, c.Model`,
    { bookingId }
  );

  const riderInfo = driverData?.[0];

  const driverProfile = useMemo(
    () => [
      {
        label: "Vehicle Number",
        value: riderInfo?.get("c.Plate"),
        icon: <VehicleIcon />,
      },
      {
        label: "Vehicle Color",
        value: riderInfo?.get("c.Color"),
        icon: <VehicleIcon />,
      },
      {
        label: "Vehicle Brand",
        value: riderInfo?.get("c.Model"),
        icon: <VehicleIcon />,
      },
      {
        label: "Riding Experience",
        value: `2.5 yrs`,
        icon: <ProfileTickBoldIcon />,
      },
      {
        label: "Vehicle Capacity",
        value: `${riderInfo?.get("c.Capacity")} Seater`,
        icon: <VehicleIcon />,
      },
    ],
    [riderInfo]
  );

  return (
    <>
      <Image src={p_map_2} w={"100%"} />
      <Grid templateColumns={"repeat(3,1fr)"} gap={6}>
        <GridItem colSpan={2}>
          <RiderProfileCard
            name={riderInfo?.get("d.Name")}
            phoneNumber={riderInfo?.get("d.Phone")}
            image={riderInfo?.get("d.Photo")}
          />
          <Grid
            templateColumns={"repeat(2,1fr)"}
            mt={6}
            gap={4}
            justifyContent={"space-between"}
          >
            {driverProfile?.map((item, index) => (
              <Stack gap={0} key={index}>
                <HStack>
                  {item.icon}
                  <Text
                    whiteSpace={"nowrap"}
                    color="gray.darkest"
                    variant={"subtitle2"}
                  >
                    {item.label}
                  </Text>
                </HStack>
                <Text variant={"pSmall"} color={"gray.normal"}>
                  {item.value}
                </Text>
              </Stack>
            ))}
          </Grid>
        </GridItem>
        <GridItem>
          <PathComponent />
        </GridItem>

        <HStack>
          <Stack color={"#0A9726"} fontWeight={600} align={"center"}>
            <Text>Fare: ${riderInfo?.get("b.Fare")}</Text>
          </Stack>
        </HStack>
      </Grid>
      
    </>
  );
};

export default RiderFound;
