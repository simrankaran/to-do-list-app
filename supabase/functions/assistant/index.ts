// AI assistant for the Tasks app.
//
// The app sends the user's message, recent chat turns and a compact snapshot
// of their tasks. Claude answers with a short reply plus a list of actions,
// which the app carries out itself (so its own rules, undo and notifications
// all still apply). The Anthropic API key stays here, as the function secret
// ANTHROPIC_API_KEY, and never reaches the app.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-opus-5-5";
const DAILY_LIMIT = 40; // messages per user per day
const MAX_MESSAGE_CHARS = 2000;
const MAX_HISTORY_TURNS = 12;
const MAX_CONTEXT_CHARS = 60000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const SYSTEM = `You are the built-in assistant of a personal to-do app called Tasks. The person chatting with you owns the task list and wants you to manage it for them: add tasks, change them, tick them off, delete them, and answer questions about what they have to do.

Every message from the user starts with a snapshot of their data: the current local date and time, their projects, and their tasks. Each task has a short reference such as t3. The snapshot is always current, so trust it over anything said earlier in the chat.

Always answer by calling the apply_changes tool exactly once. Put what you want to say to the user in "reply", and put the changes to make in "actions" (an empty list when the user only asked a question). The app carries out the actions after you answer and shows the user what happened, so in "reply" say what you are doing in a sentence or two rather than listing every field.

How to fill in actions:
- Refer to an existing task only by its reference from the snapshot (task_ref). Never invent a reference. If you cannot tell which task the user means, ask in "reply" and leave "actions" empty.
- Dates are local calendar dates as YYYY-MM-DD, and times are local 24-hour HH:MM. Work out relative dates such as "tomorrow" or "next Friday" from the date in the snapshot.
- A time slot needs start_time and end_time. If the user gives only a start time, leave end_time null and the app makes it one hour long. A time slot without a date is for today, or tomorrow if that time has already passed today.
- For update_task, set only the fields that should change and leave the rest null. To remove a due date or a time slot, use clear_due or clear_time.
- "project" is the name of one of the user's projects. Use create_project first when the user asks for a new one; a task can then use that name in the same answer.
- Use null for every field an action does not need.
- Deleting is permanent, so only delete when the user clearly asked for it. The app asks them to confirm.

Keep replies short, warm and plain. Write the way you would text a friend who asked you to sort out their day. If the user asks for something unrelated to their tasks and planning, answer briefly if it is quick, and steer back to what you can do in the app.`;

const nullableString = { type: ["string", "null"] };

const APPLY_CHANGES_TOOL: Anthropic.Beta.BetaTool = {
  name: "apply_changes",
  description:
    "Reply to the user and list the changes to make to their tasks. Call this exactly once per answer.",
  strict: true,
  input_schema: {
    type: "object",
    properties: {
      reply: {
        type: "string",
        description: "What to say to the user, in plain text.",
      },
      actions: {
        type: "array",
        description: "Changes for the app to carry out, in order.",
        items: {
          type: "object",
          properties: {
            type: {
              type: "string",
              enum: [
                "create_task",
                "update_task",
                "complete_task",
                "reopen_task",
                "delete_task",
                "create_project",
              ],
            },
            task_ref: {
              ...nullableString,
              description:
                "Reference of an existing task from the snapshot, e.g. t3. Null for create actions.",
            },
            title: {
              ...nullableString,
              description: "Task title, or the new project's name.",
            },
            notes: nullableString,
            priority: {
              type: ["string", "null"],
              enum: ["none", "low", "medium", "high", null],
            },
            due_date: {
              ...nullableString,
              description: "Local date, YYYY-MM-DD.",
            },
            start_time: {
              ...nullableString,
              description: "Local 24-hour time, HH:MM.",
            },
            end_time: {
              ...nullableString,
              description: "Local 24-hour time, HH:MM.",
            },
            project: {
              ...nullableString,
              description: "Name of the project to put the task in.",
            },
            repeat: {
              type: ["string", "null"],
              enum: ["none", "daily", "weekly", "monthly", null],
            },
            clear_due: {
              type: ["boolean", "null"],
              description: "True to remove the task's due date.",
            },
            clear_time: {
              type: ["boolean", "null"],
              description: "True to remove the task's time slot.",
            },
          },
          required: [
            "type",
            "task_ref",
            "title",
            "notes",
            "priority",
            "due_date",
            "start_time",
            "end_time",
            "project",
            "repeat",
            "clear_due",
            "clear_time",
          ],
          additionalProperties: false,
        },
      },
    },
    required: ["reply", "actions"],
    additionalProperties: false,
  },
};

interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "not_configured" }, 503);

  // Who is asking? (The platform has already checked the JWT is valid.)
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } = await userClient.auth.getUser(
    authHeader.replace(/^Bearer\s+/i, ""),
  );
  const user = userData?.user;
  if (userError || !user) return json({ error: "unauthorized" }, 401);

  // Validate the request.
  let body: {
    message?: unknown;
    history?: unknown;
    context?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const message = typeof body.message === "string" ? body.message.trim() : "";
  const context = typeof body.context === "string" ? body.context : "";
  if (!message || message.length > MAX_MESSAGE_CHARS) {
    return json({ error: "bad_request" }, 400);
  }
  if (context.length > MAX_CONTEXT_CHARS) {
    return json({ error: "too_many_tasks" }, 413);
  }
  const history: ChatTurn[] = Array.isArray(body.history)
    ? (body.history as ChatTurn[])
      .filter(
        (t) =>
          t &&
          (t.role === "user" || t.role === "assistant") &&
          typeof t.content === "string" &&
          t.content.trim().length > 0,
      )
      .slice(-MAX_HISTORY_TURNS)
      .map((t) => ({
        role: t.role,
        content: t.content.slice(0, MAX_MESSAGE_CHARS),
      }))
    : [];
  // The conversation must start with a user turn.
  while (history.length > 0 && history[0].role !== "user") history.shift();

  // Per-user daily limit, so one account can't run up the bill.
  const admin = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const today = new Date().toISOString().slice(0, 10);
  const { data: usage } = await admin
    .from("assistant_usage")
    .select("count")
    .eq("user_id", user.id)
    .eq("day", today)
    .maybeSingle();
  const used = usage?.count ?? 0;
  if (used >= DAILY_LIMIT) {
    return json({ error: "daily_limit", limit: DAILY_LIMIT }, 429);
  }
  await admin
    .from("assistant_usage")
    .upsert({ user_id: user.id, day: today, count: used + 1 });

  const client = new Anthropic({ apiKey });
  try {
    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      // A chat route: quick answers matter more than deep deliberation.
      output_config: { effort: "low" },
      // If a safety classifier declines, the API retries on a fallback model.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: SYSTEM,
      tools: [APPLY_CHANGES_TOOL],
      messages: [
        ...history,
        {
          role: "user",
          content: `<snapshot>\n${context}\n</snapshot>\n\n${message}`,
        },
      ],
    });

    if (response.stop_reason === "refusal") {
      return json({
        reply: "Sorry, I can't help with that one. Try asking another way.",
        actions: [],
      });
    }

    let reply = "";
    let actions: unknown[] = [];
    for (const block of response.content) {
      if (block.type === "text") {
        reply += block.text;
      } else if (block.type === "tool_use" && block.name === "apply_changes") {
        const input = block.input as { reply?: string; actions?: unknown[] };
        if (typeof input.reply === "string" && input.reply.trim()) {
          reply = input.reply;
        }
        if (Array.isArray(input.actions)) actions = input.actions;
      }
    }
    if (response.stop_reason === "max_tokens" && !reply) {
      reply = "That was too much to do in one go. Try a smaller request.";
    }
    return json({
      reply: reply.trim() || "Done.",
      actions,
      remaining: DAILY_LIMIT - used - 1,
    });
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) {
      console.error("Anthropic API key was rejected");
      return json({ error: "bad_api_key" }, 503);
    } else if (error instanceof Anthropic.RateLimitError) {
      return json({ error: "busy" }, 429);
    } else if (error instanceof Anthropic.APIError) {
      console.error(`Anthropic API error ${error.status}: ${error.message}`);
      return json({ error: "upstream", status: error.status }, 502);
    }
    console.error("Assistant failed", error);
    return json({ error: "internal" }, 500);
  }
});
