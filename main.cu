#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <time.h>
#include <assert.h>
#include <cuda_runtime.h>

#define MAX 1000
#define PORT 8080
#define SA struct sockaddr

#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }
inline void gpuAssert(cudaError_t code, char *file, int line, bool abort=true)
{
    if (code != cudaSuccess)
    {
        fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
        if (abort) exit(code);
    }
}

__global__ void matrixCalc(int *a, int *res, int N) {

    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (col < N) {
        int sum = 0;

        for (int k = 0; k < N; ++k) {
            int el = a[col * N + k];
            sum += el;
        }

        res[col] = sum / N;
    }


}

int counter(int res_buf, int * submit, int * res_arr, int ** arr) {

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);

    float res_time = 0;
    time_t start = clock();
    printf("INFO: Start counting \n");

    int *a, *res, *h_a;

    size_t bytes = res_buf * res_buf * sizeof(int);
    size_t bytes_res = res_buf * sizeof(int);

    h_a = (int*) malloc(bytes);

    for (int i=0; i < res_buf; i++) {
        for (int j=0; j < res_buf; j++) {
            h_a[i*res_buf + j] = arr[i][j];
            if (h_a[i*res_buf + j] == 0) {
                h_a[i*res_buf + j] = rand()%100;
            }
        }
    }

    gpuErrchk(cudaMalloc(reinterpret_cast<void **>(&a), bytes));
    gpuErrchk(cudaMemcpyAsync(a, h_a, bytes, cudaMemcpyHostToDevice));
    gpuErrchk(cudaMalloc(reinterpret_cast<void **>(&res), bytes));
    int block_size = 1024;
    int grid_size = (res_buf + block_size) / block_size;

    dim3 DimGrid(grid_size, 1,1);
    dim3 DimBlock(block_size, 1,1);

    matrixCalc<<<DimGrid,DimBlock>>>(a, res, res_buf);
    gpuErrchk( cudaPeekAtLastError() );
    gpuErrchk( cudaDeviceSynchronize() );

    gpuErrchk( cudaMemcpyAsync(res_arr, res, res_buf, cudaMemcpyDeviceToHost));

    time_t end = clock();

    res_time = ((float)(end - start) / 1000000.0F ) * 1000;
    printf("INFO: Stop counting \n");

    gpuErrchk(cudaFree( res ));
    gpuErrchk(cudaFree( a ));
    return res_time;
}

void end_transaction (int res_buf, int * submit, int * res_arr, int ** arr, int sockfd) {
    char buf[MAX];
    float res_time = counter(res_buf, submit, res_arr, arr);

    for (int i = 0; i < res_buf; i++) {
        sprintf(buf, "%d \n", res_arr[i]);
        write(sockfd, buf, sizeof(buf));
    }

    sprintf(buf, "%d", *submit / 1024);
    write(sockfd, buf, sizeof(buf));
    sprintf(buf, "%f", res_time);
    write(sockfd, buf, sizeof(buf));
    write(sockfd, "exit", sizeof("exit"));
}

int get_res_buf(char * val) {
    printf("INFO: Принятие результирующего буффера => выделение памяти %d \n", atoi(val));
    return atoi(val);
}

void func(int sockfd)
{
    char buff[MAX];
    int n;
    for (;;) {
        bzero(buff, sizeof(buff));
        printf("Enter the string from client: ");
        write(sockfd, "start", sizeof("start"));
        bzero(buff, sizeof(buff));
        read(sockfd, buff, sizeof("start"));
        printf("INFO: read %s \n", buff);

        if ((strncmp(buff, "start", sizeof("start"))) == 0) {
            int submit = 0;
            int** arr;
            int* res_arr;
            int res_buf = 0;
            int index_row = 0;
            int index_col = 0;

            printf("INFO: Start from server reciever \n");
            char *val = (char*)malloc(sizeof(buff));

            while ((strncmp(buff, "end", sizeof("end"))) != 0) {
                read(sockfd, buff, sizeof(buff));


                for (int i = 0; i < strlen(buff); i++) {


                    if (buff[i] == 's' || buff[i] == 't' ||buff[i] == 'a' ||buff[i] == 'r') {
                        continue;
                    }

                    if(buff[i] == 'e') {
                        memset(val, 0, sizeof(buff));
                        end_transaction(res_buf, &submit, res_arr, arr, sockfd);
                        return;
                    }

                    if (buff[i] == ' ') {
                        arr[index_row][index_col] = atoi(val);
                        memset(val, 0, sizeof(buff));
                        index_col++;
                        continue;
                    }

                    if (buff[i] == '\n') {

                        if (res_buf == 0) {
                            res_buf = get_res_buf(val);

                            res_arr = (int*) malloc(res_buf * sizeof(int));
                            arr = (int**) malloc(res_buf * sizeof(int*));
                            for (int j = 0; j < res_buf; j++) {
                                arr[j] = (int*) malloc(res_buf * sizeof(int));
                            }
                            memset(val, 0, sizeof(buff));
                            continue;
                        }

                        arr[index_row][index_col] = atoi(val);
                        memset(val, 0, sizeof(buff));
                        index_row++;
                        index_col = 0;
                        continue;
                    }

                    if (buff[i] != '\t'){
                        sprintf(val, "%s%c", val, buff[i]);
                    }
                }

            }
            continue;
        }

        printf("From Server : %s", buff);
        if ((strncmp(buff, "exit", 4)) == 0) {
            printf("Client Exit...\n");
            break;
        }
    }
}

int create_and_verify_socket() {
    int sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd == -1) {
        printf("ERROR: Socket creation failed...\n");
        exit(0);
    }
    printf("INFO: Socket successfully created..\n");
    return sock_fd;
}

int configure_serv_addr(struct sockaddr_in * serv_addr, int sockfd) {
    bzero(serv_addr, sizeof(*serv_addr));

    serv_addr->sin_family = AF_INET;
    serv_addr->sin_addr.s_addr = inet_addr("127.0.0.1");
    serv_addr->sin_port = htons(PORT);

    // Binding newly created socket to given IP and verification
    if ((connect(sockfd, (SA*)serv_addr, sizeof(*serv_addr))) != 0) {
        printf("ERROR: Socket bind failed...\n");
        exit(0);
    }
    else
        printf("INFO: Socket successfully binded..\n");

    return sockfd;
}

//сформировать результирующий вектор как среднее по каждой строке исходной квадратной матрицы
int main(int argc, char **argv) {

    int sockfd;
    struct sockaddr_in serv_addr;

    sockfd = create_and_verify_socket();
    configure_serv_addr(&serv_addr, sockfd);

    // main func
    func(sockfd);

    close(sockfd);
}
