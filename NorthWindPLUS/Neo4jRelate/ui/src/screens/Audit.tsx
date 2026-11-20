import { useState } from "react";
import { Badge, Box, Button, Flex, HStack, NativeSelect, Spinner, Table, Text } from "@chakra-ui/react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../api";

const SOURCES = ["simulation", "agent", "ui"];
const color = (s: string) => (s === "ui" ? "blue" : s === "agent" ? "purple" : "gray");

export default function AuditScreen() {
  const qc = useQueryClient();
  const [hours, setHours] = useState(24);
  const [source, setSource] = useState("all");
  const audit = useQuery({ queryKey: ["audit", hours], queryFn: () => api.audit(hours) });

  if (audit.isLoading) return <Spinner mt={6} />;
  if (audit.error) return <Text color="red.500" mt={4}>{(audit.error as Error).message}</Text>;
  const a = audit.data!;
  const count = (s: string, act: string) => a.activity.find((r) => r.Source === s && r.Action === act)?.POs ?? 0;
  const decisions = a.decisions.filter((d) => source === "all" || d.Source === source);

  return (
    <Box pt={4}>
      <Flex justify="space-between" align="center" mb={3} gap={3} wrap="wrap">
        <Text color="fg.muted" fontSize="sm">Three front ends, one graph: who created, resubmitted and cancelled POs, and why.</Text>
        <HStack>
          <NativeSelect.Root size="sm" w="150px">
            <NativeSelect.Field value={hours} onChange={(e) => setHours(Number(e.target.value))}>
              <option value={1}>last hour</option>
              <option value={24}>last 24 hours</option>
              <option value={168}>last 7 days</option>
            </NativeSelect.Field>
            <NativeSelect.Indicator />
          </NativeSelect.Root>
          <Button size="sm" variant="outline" onClick={() => qc.invalidateQueries({ queryKey: ["audit"] })}>Reload</Button>
        </HStack>
      </Flex>

      <Table.Root size="sm" variant="outline" mb={6} maxW="560px">
        <Table.Header>
          <Table.Row>
            <Table.ColumnHeader>Source</Table.ColumnHeader>
            <Table.ColumnHeader textAlign="end">Created</Table.ColumnHeader>
            <Table.ColumnHeader textAlign="end">Resubmitted</Table.ColumnHeader>
            <Table.ColumnHeader textAlign="end">Cancelled</Table.ColumnHeader>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {SOURCES.map((s) => (
            <Table.Row key={s}>
              <Table.Cell><Badge colorPalette={color(s)}>{s}</Badge></Table.Cell>
              <Table.Cell textAlign="end">{count(s, "created")}</Table.Cell>
              <Table.Cell textAlign="end">{count(s, "resubmitted")}</Table.Cell>
              <Table.Cell textAlign="end">{count(s, "cancelled")}</Table.Cell>
            </Table.Row>
          ))}
        </Table.Body>
      </Table.Root>

      <Flex justify="space-between" align="center" mb={2}>
        <Text fontWeight="semibold">Decisions by people (agent and UI)</Text>
        <NativeSelect.Root size="sm" w="150px">
          <NativeSelect.Field value={source} onChange={(e) => setSource(e.target.value)}>
            <option value="all">agent and UI</option>
            <option value="agent">agent only</option>
            <option value="ui">UI only</option>
          </NativeSelect.Field>
          <NativeSelect.Indicator />
        </NativeSelect.Root>
      </Flex>
      <Table.Root size="sm" variant="line">
        <Table.Header>
          <Table.Row>
            <Table.ColumnHeader>PO</Table.ColumnHeader>
            <Table.ColumnHeader>Action</Table.ColumnHeader>
            <Table.ColumnHeader>Source</Table.ColumnHeader>
            <Table.ColumnHeader>By</Table.ColumnHeader>
            <Table.ColumnHeader>When</Table.ColumnHeader>
            <Table.ColumnHeader>Justification</Table.ColumnHeader>
            <Table.ColumnHeader>Changed vs recommendation</Table.ColumnHeader>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {decisions.map((d) => (
            <Table.Row key={d.PONumber + d.Action}>
              <Table.Cell>{d.PONumber}{d.ResubmittedFrom ? ` (from ${d.ResubmittedFrom})` : ""}</Table.Cell>
              <Table.Cell>{d.Action}</Table.Cell>
              <Table.Cell><Badge colorPalette={color(d.Source)}>{d.Source}</Badge></Table.Cell>
              <Table.Cell>{d.By}</Table.Cell>
              <Table.Cell fontSize="xs">{d.Date?.slice(0, 19).replace("T", " ")}</Table.Cell>
              <Table.Cell fontSize="xs" maxW="320px">{d.Justification}</Table.Cell>
              <Table.Cell fontSize="xs">
                {d.ChangedLines.map((l) => `${l.Product}: ${l.Ordered} vs ${l.Recommended ?? "not recommended"}`).join(" · ") || "–"}
              </Table.Cell>
            </Table.Row>
          ))}
          {decisions.length === 0 && (
            <Table.Row><Table.Cell colSpan={7}>No decisions yet.</Table.Cell></Table.Row>
          )}
        </Table.Body>
      </Table.Root>
    </Box>
  );
}
