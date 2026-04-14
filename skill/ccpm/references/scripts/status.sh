#!/bin/bash

echo "Getting status..."
echo ""
echo ""


echo "📊 Project Status"
echo "================"
echo ""

echo "📄 PRDs:"
if [ -d ".qwen/prds" ]; then
  total=$(ls .qwen/prds/*.md 2>/dev/null | wc -l)
  echo "  Total: $total"
else
  echo "  No PRDs found"
fi

echo ""
echo "📚 Epics:"
if [ -d ".qwen/epics" ]; then
  total=$(ls -d .qwen/epics/*/ 2>/dev/null | grep -v '/archived/$' | wc -l)
  echo "  Total: $total"
else
  echo "  No epics found"
fi

echo ""
echo "📝 Tasks:"
if [ -d ".qwen/epics" ]; then
  total=$(find .qwen/epics -path "*/archived/*" -prune -o -name "[0-9]*.md" -print 2>/dev/null | wc -l)
  open=$(find .qwen/epics -path "*/archived/*" -prune -o -name "[0-9]*.md" -print 2>/dev/null | xargs grep -l "^status: *open" 2>/dev/null | wc -l)
  closed=$(find .qwen/epics -path "*/archived/*" -prune -o -name "[0-9]*.md" -print 2>/dev/null | xargs grep -l "^status: *closed" 2>/dev/null | wc -l)
  echo "  Open: $open"
  echo "  Closed: $closed"
  echo "  Total: $total"
else
  echo "  No tasks found"
fi

exit 0
