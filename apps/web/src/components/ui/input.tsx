import { forwardRef, type InputHTMLAttributes } from "react";
import { cn } from "../../lib/utils";

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input(
  { className, type = "text", ...props },
  ref,
) {
  return <input ref={ref} type={type} className={cn("flex h-9 w-full rounded-md border border-[#e7e6ee] bg-white px-3 py-1 text-sm text-[#292837] shadow-sm transition-colors placeholder:text-[#9997a3] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#8b80e8] disabled:cursor-not-allowed disabled:opacity-50", className)} {...props} />;
});
