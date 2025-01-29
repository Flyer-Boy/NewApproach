import { Button, Image, Text, VStack } from "@chakra-ui/react";
import { userFeedback } from "@ride-hailing/assets/images";
import { ShieldTickIcon } from "@ride-hailing/assets/svg";
import { useUserData } from "@ride-hailing/store";

const RideSuccess = () => {
  const { setReload, setStage } = useUserData();
  return (
    <>
      <VStack w={"100%"} mt={"92px"}>
        <Image src={userFeedback} w={"300px"} h={"230px"} />
        <VStack gap={1} pt={5} pb={"32px"} w={"440px"}>
          <Text fontWeight={600} fontSize={"14px"} color={"gray.darkest"}>
            Ride completed successfully !
          </Text>
          <Text variant={"pRegular"} textAlign={"center"}>
            Great job! Thanks for your service!
          </Text>
        </VStack>
      </VStack>

      <Button
        w={"full"}
        px={"32px"}
        py={"14px"}
        type="submit"
        leftIcon={<ShieldTickIcon />}
        onClick={() => {
          setReload(true);
          setStage("INITIAL");
        }}
      >
        Complete
      </Button>
    </>
  );
};

export default RideSuccess;
