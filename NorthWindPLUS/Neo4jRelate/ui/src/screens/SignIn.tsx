import { useState } from "react";
import { Alert, Box, Button, Card, Heading, HStack, NativeSelect, Spinner, Stack, Text } from "@chakra-ui/react";
import { useQuery } from "@tanstack/react-query";
import { api, User } from "../api";
import Logo from "../components/Logo";

type Result = { user: User; canUseProcurement: boolean; reason: string | null };

// A picker standing in for a login, like the agent's --as-employee. Demo only: there is no password.
export default function SignIn({ onSignedIn }: { onSignedIn: (r: Result) => void }) {
  const employees = useQuery({ queryKey: ["employees"], queryFn: api.employees });
  const [picked, setPicked] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const go = async () => {
    setBusy(true);
    setError(null);
    try {
      onSignedIn(await api.signIn(picked));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Box maxW="460px" mx="auto" mt={24} px={4}>
      <Card.Root>
        <Card.Header>
          <HStack gap={3}>
            <Logo size="56px" />
            <Box>
              <Heading size="md">NorthWind PLUS · Procurement</Heading>
              <Text color="fg.muted" fontSize="sm">Sign in as a Procurement Assistant (demo: no password).</Text>
            </Box>
          </HStack>
        </Card.Header>
        <Card.Body>
          <Stack gap={4}>
            {employees.isLoading && <Spinner />}
            {employees.error && <Text color="red.500">{(employees.error as Error).message}</Text>}
            {employees.data && (
              <NativeSelect.Root>
                <NativeSelect.Field placeholder="Choose an employee" value={picked} onChange={(e) => setPicked(e.target.value)}>
                  {employees.data.map((e) => (
                    <option key={e.employeeId} value={e.employeeId}>{e.name} (EmployeeID {e.employeeId})</option>
                  ))}
                </NativeSelect.Field>
                <NativeSelect.Indicator />
              </NativeSelect.Root>
            )}
            {error && (
              <Alert.Root status="error"><Alert.Indicator /><Alert.Description>{error}</Alert.Description></Alert.Root>
            )}
            <Button onClick={go} disabled={!picked} loading={busy}>Sign in</Button>
          </Stack>
        </Card.Body>
      </Card.Root>
    </Box>
  );
}
