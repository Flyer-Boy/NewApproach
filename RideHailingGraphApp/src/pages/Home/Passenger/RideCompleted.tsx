import {
  Box,
  Button,
  HStack,
  Image,
  Switch,
  Text,
  VStack,
} from "@chakra-ui/react";
import { userFeedback } from "@ride-hailing/assets/images";
import {
  InformationIcon,
  ShieldTickIcon,
  UnFilledStarIcon,
} from "@ride-hailing/assets/svg";
import { useUserData } from "@ride-hailing/store";
import { useState } from "react";

const RideCompleted = () => {
  const [rating, setRating] = useState(0);

  const { setStage, setReload, setBookingId } = useUserData();

  return (
    <>
      <VStack w={"100%"} align={"center"}>
        <Image src={userFeedback} w={"300px"} h={"200px"} />
        <VStack gap={1} pt={5} pb={"32px"} w={"440px"}>
          <Text fontWeight={600} fontSize={"14px"} color={"gray.darkest"}>
            Ride Completed Successfully !
          </Text>
          <Text variant={"pRegular"}>
            Great job! You travelled 15 km in 25 minutes. Thank you for choosing
            our service!
          </Text>
        </VStack>
        <VStack bgColor={"#E6E6E6"} p={6} borderRadius={"xl"} w={"440px"}>
          <Text pb={2} variant={"subtitle2"}>
            How was your trip with {}?
          </Text>
          <HStack>
            {Array.from({ length: 5 }).map((_, index) => (
              <Box
                key={index}
                sx={{
                  svg: {
                    path: {
                      fill: index < rating ? "#FFBE26" : "",
                      stroke: index < rating ? "#FFBE26" : "",
                    },
                  },
                }}
                onClick={() => setRating(index + 1)}
                cursor={"pointer"}
              >
                <UnFilledStarIcon />
              </Box>
            ))}
          </HStack>
        </VStack>
      </VStack>
      <HStack
        justifyContent={"space-between"}
        w={"100%"}
        p={"9px 12px"}
        border={"1px solid"}
        borderColor={"gray.light"}
        borderRadius={"12px"}
      >
        <HStack>
          <InformationIcon />
          <Text color={"gray.normal"} variant={"pNormal"}>
            Do you have any words about ride?{" "}
          </Text>
        </HStack>
        <Switch isChecked />
      </HStack>
      <Button
        w={"full"}
        px={"32px"}
        py={"14px"}
        type="submit"
        leftIcon={<ShieldTickIcon />}
        onClick={() => {
          setStage("INITIAL");
          setReload(true);
          setBookingId("");
        }}
      >
        Submit
      </Button>
    </>
  );
};

export default RideCompleted;
