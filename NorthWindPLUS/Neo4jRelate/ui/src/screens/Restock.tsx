import { useEffect, useState } from "react";
import { Alert, Box, Button, Flex, HStack, List, Spinner, Text } from "@chakra-ui/react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api, money, refreshAfterWrite, Review } from "../api";
import POCard, { CardState, initialState, itemsOf } from "../components/POCard";
import ReviewDialog from "../components/ReviewDialog";
import ActionBar from "../components/ActionBar";

type Outcome = Awaited<ReturnType<typeof api.commitCreate>>;

export default function Restock({ drafts }: { drafts: boolean }) {
  const qc = useQueryClient();
  const rec = useQuery({ queryKey: ["restock"], queryFn: api.restock });
  const [cards, setCards] = useState<Record<string, CardState>>({});
  const [review, setReview] = useState<Review | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [submitted, setSubmitted] = useState<Set<string>>(new Set());   // hidden at once, until the reload arrives

  useEffect(() => {
    // Every card starts left out: pick the POs to create now (each one you include needs a justification).
    if (rec.data) setCards(Object.fromEntries(rec.data.rows.map((r) => [r.SupplierID, initialState(r.Lines, false)])));
    setSubmitted(new Set());
    // dataUpdatedAt too: a reload that returns identical data keeps the same object, and the cards must still reset
  }, [rec.data, rec.dataUpdatedAt]);

  const reload = () => { setOutcome(null); setError(null); qc.invalidateQueries({ queryKey: ["restock"] }); };
  const visible = (rec.data?.rows ?? []).filter((r) => !submitted.has(r.SupplierID));
  const included = visible.filter((r) => cards[r.SupplierID]?.include);

  const toReview = async () => {
    setError(null);
    try {
      setReview(await api.previewCreate(included.map((r) => ({
        supplierId: r.SupplierID, items: itemsOf(cards[r.SupplierID]), justification: cards[r.SupplierID].justification,
      }))));
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const confirm = async (previewId: string) => {
    const out = await api.commitCreate(previewId);
    setReview(null);
    setOutcome(out);
    setSubmitted(new Set(included.map((r) => r.SupplierID)));
    refreshAfterWrite(qc);     // reload every screen from the graph (the API also needs a fresh recommendation)
  };

  if (rec.isLoading) return <Spinner mt={6} />;
  if (rec.error) return <Text color="red.500" mt={4}>{(rec.error as Error).message}</Text>;
  const rows = visible;

  return (
    <Box pt={4}>
      <Flex justify="space-between" align="center" mb={3}>
        <Text color="fg.muted" fontSize="sm">
          What needs restocking now: the simulation's own rule (effective stock near the restock threshold), one PO per Supplier.
          Include the ones to create, then Review at the bottom of the window.
        </Text>
        <HStack>
          {rec.isFetching && <><Spinner size="xs" /><Text fontSize="xs" color="fg.muted">Reloading from the graph…</Text></>}
          <Button size="sm" variant="outline" onClick={reload} disabled={rec.isFetching}>Reload from the graph</Button>
        </HStack>
      </Flex>
      {rec.data?.warning && (
        <Alert.Root status="warning" mb={3}><Alert.Indicator /><Alert.Description>{rec.data.warning}</Alert.Description></Alert.Root>
      )}
      {outcome && (
        <Alert.Root status="success" mb={3}>
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>Created {outcome.created.length} PO(s). The lists below are reloaded from the graph.</Alert.Title>
            <Alert.Description>
              <List.Root ps={4}>
                {outcome.created.map((c) => <List.Item key={c.PONumber}>{c.PONumber}: est. {money(c.EstimatedCost)}, goes to {c.approvalLevel}</List.Item>)}
                {outcome.left_out.map((l, i) => <List.Item key={i}>Left out {l.product}: {l.reason}</List.Item>)}
              </List.Root>
            </Alert.Description>
          </Alert.Content>
        </Alert.Root>
      )}
      {rows.length === 0 && <Text mt={4}>Nothing needs restocking right now.</Text>}
      {rows.map((r) => cards[r.SupplierID] && (
        <POCard key={r.SupplierID} title={r.Supplier} subtitle={`Supplier ${r.SupplierID}`} lines={r.Lines} demand={r.demand}
                state={cards[r.SupplierID]} drafts={drafts}
                onChange={(s) => setCards({ ...cards, [r.SupplierID]: s })}
                draftRequest={async () => (await api.draft({ kind: "create", supplierId: r.SupplierID, items: itemsOf(cards[r.SupplierID]) })).draft}
                actions={
                  <Button size="xs" variant={cards[r.SupplierID].include ? "outline" : "solid"}
                          onClick={() => setCards({ ...cards, [r.SupplierID]: { ...cards[r.SupplierID], include: !cards[r.SupplierID].include } })}>
                    {cards[r.SupplierID].include ? "Leave out" : "Include"}
                  </Button>
                } />
      ))}
      {error && <Alert.Root status="error" mb={3}><Alert.Indicator /><Alert.Description>{error}</Alert.Description></Alert.Root>}
      {rows.length > 0 && (
        <ActionBar>
          <Text fontSize="sm" color="fg.muted">
            {included.length === 0
              ? `${rows.length} recommended PO(s). Click Include on the ones to create now.`
              : `${included.length} of ${rows.length} included · each needs a justification`}
          </Text>
          <Button colorPalette="blue" disabled={included.length === 0 || rec.isFetching} onClick={toReview}>
            {rec.isFetching ? "Reloading…" : `Review ${included.length} PO(s)`}
          </Button>
        </ActionBar>
      )}
      <ReviewDialog review={review} verb="Create POs" onClose={() => setReview(null)} onConfirm={confirm} />
    </Box>
  );
}
