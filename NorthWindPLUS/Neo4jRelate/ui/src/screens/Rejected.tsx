import { useEffect, useState } from "react";
import { Alert, Box, Button, Card, Flex, HStack, List, Spinner, Text, Textarea } from "@chakra-ui/react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api, money, refreshAfterWrite, ResubRow, Review } from "../api";
import POCard, { CardState, initialState, itemsOf } from "../components/POCard";
import ReviewDialog from "../components/ReviewDialog";
import ActionBar from "../components/ActionBar";

type Choice = "none" | "resubmit" | "cancel";
type Row = { choice: Choice; card: CardState; reason: string };

export default function Rejected({ drafts, me }: { drafts: boolean; me: string }) {
  const qc = useQueryClient();
  const rec = useQuery({ queryKey: ["resubmissions"], queryFn: api.resubmissions });
  const [rows, setRows] = useState<Record<string, Row>>({});
  const [review, setReview] = useState<{ kind: "resubmit" | "cancel"; data: Review } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string[] | null>(null);
  const [drafting, setDrafting] = useState<string | null>(null);

  useEffect(() => {
    if (rec.data) setRows(Object.fromEntries(rec.data.rows.map((r) => [r.RejectedPO, {
      choice: "none" as Choice, card: initialState(r.Lines, true), reason: "",
    }])));
  }, [rec.data]);

  const set = (po: string, patch: Partial<Row>) => setRows({ ...rows, [po]: { ...rows[po], ...patch } });
  const list = rec.data?.rows ?? [];
  const resubs = list.filter((r) => rows[r.RejectedPO]?.choice === "resubmit");
  const cancels = list.filter((r) => rows[r.RejectedPO]?.choice === "cancel");

  const after = (lines: string[]) => {
    setReview(null);
    setMessage([...lines, "The list below is reloaded from the graph."]);
    refreshAfterWrite(qc);
  };

  const reviewResubmit = async () => {
    setError(null);
    try {
      setReview({ kind: "resubmit", data: await api.previewResubmit(resubs.map((r) => ({
        rejectedPO: r.RejectedPO, items: itemsOf(rows[r.RejectedPO].card), justification: rows[r.RejectedPO].card.justification,
      }))) });
    } catch (e) { setError((e as Error).message); }
  };

  const reviewCancel = async () => {
    setError(null);
    try {
      setReview({ kind: "cancel", data: await api.previewCancel(cancels.map((r) => ({
        rejectedPO: r.RejectedPO, justification: rows[r.RejectedPO].reason,
      }))) });
    } catch (e) { setError((e as Error).message); }
  };

  const confirm = async (previewId: string) => {
    if (review?.kind === "resubmit") {
      const out = await api.commitResubmit(previewId);
      after([
        ...out.resubmitted.map((x) => `${x.ResubmittedFrom} resubmitted as ${x.PONumber}: est. ${money(x.EstimatedCost)}, goes to ${x.approvalLevel}`),
        ...out.left_out.map((x) => `Left out ${x.product}: ${x.reason}`),
        ...out.not_resubmitted.map((x) => `${x.rejectedPO} not resubmitted: ${x.reason}`),
      ]);
    } else {
      const out = await api.commitCancel(previewId);
      after([...out.cancelled.map((po) => `${po} cancelled`), ...out.not_cancelled.map((x) => `${x.rejectedPO} not cancelled: ${x.reason}`)]);
    }
  };

  const draftCancel = async (r: ResubRow) => {
    setDrafting(r.RejectedPO);
    try { set(r.RejectedPO, { reason: (await api.draft({ kind: "cancel", rejectedPO: r.RejectedPO })).draft }); }
    catch (e) { setError((e as Error).message); }
    finally { setDrafting(null); }
  };

  if (rec.isLoading) return <Spinner mt={6} />;
  if (rec.error) return <Text color="red.500" mt={4}>{(rec.error as Error).message}</Text>;

  const chooser = (r: ResubRow) => {
    const resubmittable = r.EstimatedCost > 0;
    const c = rows[r.RejectedPO]?.choice;
    return (
      <HStack>
        <Button size="xs" variant={c === "resubmit" ? "solid" : "outline"} disabled={!resubmittable}
                onClick={() => set(r.RejectedPO, { choice: c === "resubmit" ? "none" : "resubmit" })}>Resubmit</Button>
        <Button size="xs" variant={c === "cancel" ? "solid" : "outline"} colorPalette="red"
                onClick={() => set(r.RejectedPO, { choice: c === "cancel" ? "none" : "cancel" })}>Cancel PO</Button>
      </HStack>
    );
  };

  const raised = (r: ResubRow) => !r.RaisedBy ? "Raised by: not recorded" :
    `Raised by ${r.RaisedBy.EmployeeID === me ? "you" : r.RaisedBy.Name} (EmployeeID ${r.RaisedBy.EmployeeID}` +
    `${r.RaisedBy.Source ? `, via ${r.RaisedBy.Source}` : ""})`;
  const who = (r: ResubRow) => (
    <>
      <Text as="span" fontWeight="medium" color="fg">{raised(r)}</Text>
      {" · "}{r.Supplier}
      {r.Rejection?.RejectedBy && <> · rejected at {r.Rejection.Level} by {r.Rejection.RejectedBy}: “{r.Rejection.Comment ?? "no comment"}”</>}
    </>
  );

  return (
    <Box pt={4}>
      <Flex justify="space-between" align="center" mb={3}>
        <Text color="fg.muted" fontSize="sm">
          Rejected POs not yet resubmitted or cancelled, with what is still needed now (the loops' resubmission rule).
          This is the procurement team's shared queue: any Procurement Assistant can resubmit or cancel a rejected PO,
          including one raised by someone else. The audit trail records who raised it and who decided.
        </Text>
        <Button size="sm" variant="outline" onClick={() => { setMessage(null); qc.invalidateQueries({ queryKey: ["resubmissions"] }); }}>
          Reload from the graph
        </Button>
      </Flex>
      {rec.data?.warning && <Alert.Root status="warning" mb={3}><Alert.Indicator /><Alert.Description>{rec.data.warning}</Alert.Description></Alert.Root>}
      {message && (
        <Alert.Root status="success" mb={3}><Alert.Indicator />
          <Alert.Description><List.Root ps={4}>{message.map((m, i) => <List.Item key={i}>{m}</List.Item>)}</List.Root></Alert.Description>
        </Alert.Root>
      )}
      {list.length === 0 && <Text mt={4}>No rejected POs are waiting for a decision.</Text>}
      {list.map((r) => {
        const row = rows[r.RejectedPO];
        if (!row) return null;
        if (row.choice === "resubmit") {
          return (
            <POCard key={r.RejectedPO} title={`${r.RejectedPO} → resubmit`} subtitle={who(r)} lines={r.Lines} demand={r.demand}
                    state={row.card} drafts={drafts} showRejected onChange={(card) => set(r.RejectedPO, { card })}
                    draftRequest={async () => (await api.draft({ kind: "resubmit", rejectedPO: r.RejectedPO, items: itemsOf(row.card) })).draft}
                    actions={chooser(r)} />
          );
        }
        return (
          <Card.Root key={r.RejectedPO} variant="outline" mb={4}>
            <Card.Body>
              <Flex justify="space-between" align="start" gap={3} wrap="wrap">
                <Box>
                  <Text fontWeight="semibold">{r.RejectedPO}</Text>
                  <Box fontSize="sm" color="fg.muted">{who(r)}</Box>
                  <Text fontSize="sm" mt={1}>
                    {r.Lines.map((l) => `${l.Product}: rejected ${l.RejectedQt}, still needed ${l.RecommendedQt || 0}`).join(" · ")}
                  </Text>
                  <Text fontSize="sm" color="fg.muted">{r.ApprovalLevelNeeded}{r.EstimatedCost > 0 ? ` · est. ${money(r.EstimatedCost)}` : ""}</Text>
                </Box>
                {chooser(r)}
              </Flex>
              {row.choice === "cancel" && (
                <Box mt={3}>
                  <Flex justify="space-between" align="center" mb={1}>
                    <Text fontSize="sm" fontWeight="medium">Reason for cancelling (required, recorded with the PO)</Text>
                    {drafts && <Button size="xs" variant="outline" loading={drafting === r.RejectedPO} onClick={() => draftCancel(r)}>Suggest (AI draft)</Button>}
                  </Flex>
                  <Textarea size="sm" rows={2} value={row.reason} onChange={(e) => set(r.RejectedPO, { reason: e.target.value })} />
                </Box>
              )}
            </Card.Body>
          </Card.Root>
        );
      })}
      {error && <Alert.Root status="error" mb={3}><Alert.Indicator /><Alert.Description>{error}</Alert.Description></Alert.Root>}
      {list.length > 0 && (
        <ActionBar>
          <Text fontSize="sm" color="fg.muted">Choose Resubmit or Cancel PO on the ones to decide now.</Text>
          <Flex gap={3}>
            <Button colorPalette="red" variant="outline" disabled={!cancels.length} onClick={reviewCancel}>Review {cancels.length} cancellation(s)</Button>
            <Button colorPalette="blue" disabled={!resubs.length} onClick={reviewResubmit}>Review {resubs.length} resubmission(s)</Button>
          </Flex>
        </ActionBar>
      )}
      <ReviewDialog review={review?.data ?? null} verb={review?.kind === "cancel" ? "Cancel POs" : "Resubmit POs"}
                    onClose={() => setReview(null)} onConfirm={confirm} />
    </Box>
  );
}
