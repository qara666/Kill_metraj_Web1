@echo off
if exist "test.bat" (
  echo "test.bat exists"
) else if not exist "nonexistent" (
  echo "nonexistent missing"
)
echo "done"
