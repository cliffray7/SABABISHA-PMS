import type { HTMLAttributes } from "react";
import { cn } from "../../lib/utils";

export function Badge({ className, ...props }: HTMLAttributes<HTMLSpanElement>) {
  return <span className={cn("inline-flex items-center rounded-md border border-transparent bg-[#eeedf9] px-2 py-1 text-[11px] font-medium text-[#6659c9]", className)} {...props} />;
}
