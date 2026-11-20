import { useState } from "react";
import { Alert, Badge, Box, Button, Flex, Heading, HStack, Tabs, Text } from "@chakra-ui/react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api, User } from "./api";
import SignIn from "./screens/SignIn";
import Restock from "./screens/Restock";
import Rejected from "./screens/Rejected";
import AuditScreen from "./screens/Audit";
import Logo from "./components/Logo";

export default function App() {
  const [session, setSession] = useState<{ user: User; can: boolean; reason: string | null } | null>(null);
  const qc = useQueryClient();
  const config = useQuery({ queryKey: ["config"], queryFn: api.config });
  const status = useQuery({ queryKey: ["status"], queryFn: api.status, enabled: !!session, refetchInterval: 30_000 });

  if (!session) {
    return <SignIn onSignedIn={(r) => setSession({ user: r.user, can: r.canUseProcurement, reason: r.reason })} />;
  }

  const signOut = async () => {
    await api.signOut().catch(() => undefined);
    qc.clear();
    setSession(null);
  };

  const loops = status.data?.loops;
  return (
    <Box maxW="1200px" mx="auto" p={6}>
      <Flex justify="space-between" align="center" mb={4} gap={4} wrap="wrap">
        <HStack gap={3} align="center">
          <Logo size="48px" />
          <Box>
          <Heading size="lg">NorthWind PLUS · Procurement</Heading>
          <Text color="fg.muted" fontSize="sm">
            Same governed Cypher as the AI agent and the simulation loops · every PO written here records Source "ui"
          </Text>
          </Box>
        </HStack>
        <HStack>
          <Badge colorPalette={config.data?.mode === "agents" ? "green" : "orange"}>mode: {config.data?.mode ?? "…"}</Badge>
          {status.data && (
            <Badge colorPalette="gray">
              L1 ≤ {status.data.limits.l1.toLocaleString()} · L2 ≤ {status.data.limits.l2.toLocaleString()} · L3 ≤{" "}
              {status.data.limits.l3.toLocaleString()}
            </Badge>
          )}
          <Text fontSize="sm">{session.user.name}</Text>
          <Button size="xs" variant="outline" onClick={signOut}>Sign out</Button>
        </HStack>
      </Flex>

      {!session.can && (
        <Alert.Root status="warning" mb={4}>
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>Procurement isn't available in this session</Alert.Title>
            <Alert.Description>{session.reason}</Alert.Description>
          </Alert.Content>
        </Alert.Root>
      )}
      {session.can && loops && (loops.created > 0 || loops.resubmitted > 0) && (
        <Alert.Root status="warning" mb={4}>
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>A simulation loop still seems to be doing this job</Alert.Title>
            <Alert.Description>
              In the last few minutes the simulation created {loops.created} and resubmitted {loops.resubmitted} PO(s).
              You can review recommendations, but writes are refused until it stops (run_loops_agents.bat doesn't start it).
            </Alert.Description>
          </Alert.Content>
        </Alert.Root>
      )}

      {session.can && (
        <Tabs.Root defaultValue="restock" lazyMount unmountOnExit={false}>
          <Tabs.List>
            <Tabs.Trigger value="restock">Restock</Tabs.Trigger>
            <Tabs.Trigger value="rejected">Rejected POs</Tabs.Trigger>
            <Tabs.Trigger value="audit">Audit</Tabs.Trigger>
          </Tabs.List>
          <Tabs.Content value="restock"><Restock drafts={!!config.data?.drafts} /></Tabs.Content>
          <Tabs.Content value="rejected"><Rejected drafts={!!config.data?.drafts} me={session.user.employeeId} /></Tabs.Content>
          <Tabs.Content value="audit"><AuditScreen /></Tabs.Content>
        </Tabs.Root>
      )}
    </Box>
  );
}
