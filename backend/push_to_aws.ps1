# 🚀 AWS ECR Push Script (Industrial Style)
# Run this script from the backend directory to build and push your latest changes.

Write-Host "🏗️  Starting Docker Build..." -ForegroundColor Cyan
docker build -t testpro-backend .

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker build failed. Please ensure Docker Desktop is running." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "🏷️  Tagging Image..." -ForegroundColor Cyan
docker tag testpro-backend:latest 978850044004.dkr.ecr.ap-south-2.amazonaws.com/testpro-backend:latest

Write-Host "🔐 Logging in to AWS ECR (ap-south-2)..." -ForegroundColor Cyan
aws ecr get-login-password --region ap-south-2 | docker login --username AWS --password-stdin 978850044004.dkr.ecr.ap-south-2.amazonaws.com

Write-Host "⬆️  Pushing to ECR..." -ForegroundColor Cyan
docker push 978850044004.dkr.ecr.ap-south-2.amazonaws.com/testpro-backend:latest

Write-Host "`n✅ SUCCESS: Image pushed to ECR!" -ForegroundColor Green
Write-Host "Next Steps:"
Write-Host "1. ssh -i testpro-key.pem ubuntu@18.61.65.8"
Write-Host "2. sudo docker pull 978850044004.dkr.ecr.ap-south-2.amazonaws.com/testpro-backend:latest"
Write-Host "3. sudo docker stop testpro-api; sudo docker rm testpro-api"
Write-Host "4. sudo docker run -d --name testpro-api --restart always -p 80:4000 -v /home/ubuntu/.env:/app/.env 978850044004.dkr.ecr.ap-south-2.amazonaws.com/testpro-backend:latest"
