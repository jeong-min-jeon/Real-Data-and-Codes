# R code for function-on-scalar nw estimator for electricity data

# Load necessary packages
library(readxl)
library(pracma)
library(pdist)

# Load necessary source file
source('C:/Downloads/R_functions_for_pre-smoothing.R')

# Get response
electricity=read_xlsx('C:/Downloads/electricity.xlsx') # path of the electricity.xlsx file
Y_raw=t(electricity[,-1]) # make response as a (sample size,number of observed  times) matrix
n=nrow(Y_raw)
T=ncol(Y_raw)

# Pre-smoothing step
time_vector=seq(0,1,length=T) # equally-spaced observed times re-scailed on [0,1]
eval_points=277 # number of evaluation time points
eval_vector=seq(0,1,length=eval_points) # vector of evaluation time points
h_add=0.1 # (minimum bandwidth,minimum bandwidth+h_add) will be the range for candidate bandwidths 
h_length=101 # number of candidate bandwidths
pre_smoothing_h=c() # its i-th component will be an optimal bandwidth for pre-smoothing the i-th curve
Y=matrix(,n,eval_points) # pre-smoothed response matrix
for(i in 1:n)
{
  pre_smoothing_h[i]=optimal_h_loocv(time_vector,Y_raw[i,],h_add,h_length)$h_optimal
  for(t in 1:eval_points)
  {
    Y[i,t]=nw(eval_vector[t],time_vector,Y_raw[i,],pre_smoothing_h[i])
  }
}

# Get predictor
X1=read_xlsx('C:/Downloads/temperature.xlsx')[,2] # path of the temperature.xlsx file
X2=read_xlsx('C:/Downloads/cloudiness.xlsx')[,2] # path of the cloudiness.xlsx file
X=cbind(X1,X2)
X=as.matrix(X)
d=ncol(X)

# Re-scale X for better result
for(j in 1:d)
{
  X[,j]=(X[,j]-min(X[,j]))/(max(X[,j])-min(X[,j]))
}

# Kernel function for the nw
K=function(x)
{
  3/4*(1-x^2)*dunif(x,-1,1)*2
}

# Vectorized trapzoidal integration
int<-function(x,y)
{
  index = 2:length(x)
  ((x[index] - x[index-1]) %*% (y[index,] + y[index-1,])) / 2
}

# Function for prediction for the nw for L2 response
# x: target x (matrix whose column is the number of covariates)
# X: observed X (matrix of size (sample size,the number of covariates))
# Y: observed Y (matrix of size (sample size,the number of evaluation time points))
# h: bandwidth
predict_nw_L2=function(x,X,Y,h)
{
  N=nrow(x)
  n=nrow(X)
  T=ncol(Y)
  predict=matrix(0,nrow=N,ncol=T)
  K_values=matrix(0,nrow=N,ncol=n)
  for(p in 1:N)
  {
    K_values[p,]=K(as.matrix(pdist(x[p,],X))/h)
    below=sum(K_values[p,])
    upper=colSums(K_values[p,]*Y)
    predict[p,]=upper/below
  }
  return(predict)
}

# Function for cross-validatory optimal h for the nw for L2 response
# X: observed X (matrix of size (sample size,the number of covariates))
# Y: observed Y (matrix of size (sample size,the number of evaluation time points))
# time_vector: time vector for Y
# nfolds: the number of folds for cross-validation
# h_add and h_length: seq(min_h,min_h+h_add,length=h_length) will be the set of candidate bandwidths
# for some small bandwidth min_h which makes kernel smoothing possible
optimal_h_L2=function(X,Y,time_vector,nfolds,h_add,h_length)
{
  n=nrow(X)
  d=ncol(X)
  s=sample(n)
  X=X[s,]
  Y=Y[s,]
  folds=cut(1:n,breaks=nfolds,labels=FALSE)
  distance=c()
  for(k in 1:nfolds)
  {
    X.training=X[-which(folds==k),]
    X.test=matrix(X[which(folds==k),],ncol=d)
    new.distance=c()
    for(p in 1:nrow(X.test))
    {
      new.distance[p]=min(as.matrix(pdist(matrix(X.test[p,],ncol=d),X.training)))
    }
    distance[k]=max(new.distance)
  }
  min_h=max(distance)+0.001
  h_vector=seq(min_h,min_h+h_add,length=h_length)
  error.fold=c()
  error.h=c()
  for(j in 1:h_length)
  {
    for(k in 1:nfolds)
    {
      X.training=X[-which(folds==k),]
      X.test=X[which(folds==k),]
      Y.training=Y[-which(folds==k),]
      Y.test=Y[which(folds==k),]
      Y.test.hat=predict_nw_L2(matrix(X.test,ncol=d),X.training,Y.training,h_vector[j])
      if(length(which(folds==k))>1) error.fold[k]=sum(int(time_vector,(t(Y.test)-t(Y.test.hat))^2))
      if(length(which(folds==k))==1) error.fold[k]=trapz(time_vector,(Y.test-Y.test.hat)^2)
    }
    error.h[j]=sum(error.fold)
  }
  return(list(h_optimal=min(h_vector[which.min(error.h)]),h_initial=min_h))
}

Y_hat=matrix(,n,eval_points)
error=c()
h_selected=c()

# Get ASPE
# when i=95, NaN is produced because selected bandwidth is too small
# when i=95, one can use min(as.matrix(pdist(matrix(X[i,],ncol=d),X[-i,])))+0.001 as bandwidth
# (0.001 is just an arbitrary small value)
for(i in 1:n)
{
  print(i)
  if(i!=95)
  {
    h_selected[i]=optimal_h_L2(X[-i,],Y[-i,],eval_vector,nfolds=10,h_add=0.2,h_length=201)$h_optimal
    Y_hat[i,]=predict_nw_L2(matrix(X[i,],ncol=d),X[-i,],Y[-i,],h_selected[i])
    error[i]=trapz(eval_vector,(Y[i,]-Y_hat[i,])^2)
  }
  if(i==95)
  {
    h_selected[i]=min(as.matrix(pdist(matrix(X[i,],ncol=d),X[-i,])))+0.001
    Y_hat[i,]=predict_nw_L2(matrix(X[i,],ncol=d),X[-i,],Y[-i,],h_selected[i])
    error[i]=trapz(eval_vector,(Y[i,]-Y_hat[i,])^2)
  }
}

mean(error)
