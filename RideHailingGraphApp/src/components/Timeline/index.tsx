import { Box, Center, HStack, Stack, Text } from "@chakra-ui/react";
import { VanIcon } from "@ride-hailing/assets/svg";
import { useUserData } from "@ride-hailing/store";
import { useMemo } from "react";

const rideStatus = [
  "Ride accepted",
  "Moving towards location",
  "Ride Started",
  "Moving towards destination",
  "Ride completed",
];

const rideStatusCode = {
  NEUTRAL: 0,
  RIDE_ACCEPTED: 2,
  RIDE_STARTED: 4,
  RIDE_COMPLETED: 5,
};

const Timeline = () => {
  const { stage } = useUserData();
  const rideStage = useMemo(() => {
    return rideStatusCode[stage as unknown as "NEUTRAL"];
  }, [stage]);

  return (
    <Stack>
      {rideStatus?.map((item, index) => (
        <>
          <HStack>
            <Center
              bg={index < rideStage ? "success.400" : "gray.normal"}
              borderRadius={"50%"}
              boxSize={"24px"}
            >
              <VanIcon />
            </Center>
            <Text key={index}>{item}</Text>
          </HStack>
          {index < rideStatus.length - 1 && (
            <Box
              borderLeft={"2px dashed #C2C2C2"}
              h={"18px"}
              w={"2px"}
              ml={2}
            ></Box>
          )}
        </>
      ))}
    </Stack>
  );
};

export default Timeline;
