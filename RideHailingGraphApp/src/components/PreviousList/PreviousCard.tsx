import { Avatar, Box, HStack, Stack, Text } from "@chakra-ui/react";
import { PreviousCardTypes } from "@ride-hailing/@types/props";
import { VehicleIcon } from "@ride-hailing/assets/svg";

const Previouscard = ({ data }: { data: PreviousCardTypes }) => {
  const { name, phoneNumber, pickUp, dropOff, photo, fare, date } = data;

  return (
    <HStack
      justifyContent={"space-between"}
      alignItems={"center"}
      gap={0}
      border={"1px solid #ebebeb"}
      p={5}
      borderRadius={"2xl"}
    >
      <HStack flex={1} mr={"50px"}>
        <Avatar src={photo} name="Biplov" size={"lg"} />
        <Stack gap={0}>
          <Text fontSize={"sm"} fontWeight={600}>
            {name}
          </Text>
          <Text fontSize={"13px"} fontWeight={400}>
            Ph: {phoneNumber}
          </Text>
        </Stack>
      </HStack>

      <Stack alignItems={"center"} gap={0} color={"gray.dark"} flex={1}>
        <HStack alignItems={"center"}>
          <Text> When: {date}</Text>
        </HStack>

        <HStack justifyContent="space-between" alignItems={"center"}>
          <Box>
            <VehicleIcon />
          </Box>
          <Text
            whiteSpace={"nowrap"}
            color="gray.darkest"
            fontWeight={600}
            fontSize="sm"
          >
            {pickUp.split(",").slice(0, 3).join(",")} →{" "}
            {dropOff.split(",").slice(0, 3).join(",")}
          </Text>
        </HStack>
        <HStack>
          <HStack>
            <Stack gap={0} flex={1} textAlign={"right"}>
              <Text color={"#0A9726"} fontWeight={600}>
                Fare: ${fare}
              </Text>
            </Stack>
          </HStack>
        </HStack>
      </Stack>
    </HStack>
  );
};

export default Previouscard;
