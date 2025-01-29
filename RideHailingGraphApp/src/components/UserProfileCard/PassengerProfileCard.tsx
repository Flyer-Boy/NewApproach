import { Center } from "@chakra-ui/react";
import UserProfileCard from ".";
import { useReadCypher } from "use-neo4j";
import CustomSpinner from "../Spinner";

const PassengerProfileCard = () => {
  const userTypeId = localStorage.getItem("userTypeId");

  const query = `MATCH (p:Passenger {Phone: $id}) RETURN p`;

  const { records, loading } = useReadCypher(query, { id: userTypeId });

  if (loading) {
    return (
      <Center h={"100%"}>
        <CustomSpinner />
      </Center>
    );
  }

  const data = records?.[0]?.get("p").properties;
  return <UserProfileCard data={data} />;
};

export default PassengerProfileCard;
