#include <stdio.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <time.h>
#include <math.h>
#define MAX_SOCKET_DATA_BATCH 1000
#define PORT 8080
#define MATRIX_PATH "./matrix.txt"
#define RES_PATH "./res.txt"
#define MB_TO_KB 1024
#define SA struct sockaddr

FILE* get_fd(char * path, char * mode) {
    FILE *f;
    f = fopen(path,mode);
    if(!f) {
        printf("ERROR: Error open %s in mode %s \n", path, mode);
        return f;
    }
    printf("INFO: File %s in mode %s successfully opened\n", path, mode);
    return f;
}

void send_file(FILE *fp, int sockfd){
    char data[MAX_SOCKET_DATA_BATCH] = {0};

    while(fgets(data, MAX_SOCKET_DATA_BATCH, fp) != NULL) {
        if (send(sockfd, data, sizeof(data), 0) == -1) {
            perror("[-]Error in sending file.");
            exit(1);
        }
        bzero(data, MAX_SOCKET_DATA_BATCH);
    }
}

char* conver_digit_into_char(int digit) {
    char* str = malloc(MAX_SOCKET_DATA_BATCH * sizeof(char));
    sprintf(str, "%d\n", digit);
    return str;
}

void handle_send_file(int connfd, int num_of_rows) {
    FILE *f = get_fd(MATRIX_PATH,"r");
    printf("INFO: Start sending info \n");

    write(connfd, "start", sizeof("start"));

    char* resBuf = conver_digit_into_char(num_of_rows);
    printf("INFO: Sending number of rows %s\n", resBuf);
    write(connfd, resBuf, sizeof(resBuf));

    printf("INFO: Sending file \n");
    send_file(f, connfd);

    write(connfd, "end", sizeof("end"));
    printf("INFO: End of sending file \n");
}

void func(int connfd, int num_of_rows)
{
    char buff[MAX_SOCKET_DATA_BATCH];

    FILE *fres;
    fres = get_fd(RES_PATH, "w+");

    // infinite loop for chat
    for (;;) {

        bzero(buff, MAX_SOCKET_DATA_BATCH);
        // read the message from client and copy it in buffer
        read(connfd, buff, sizeof(buff));

        if (strcmp(buff, "") != 0) {

            if (strncmp("exit", buff, 4) == 0) {
                fclose(fres);
                printf("INFO: Server Exit...\n");
                break;
            }

            if ((strncmp(buff, "start", 5)) == 0) {
                handle_send_file(connfd, num_of_rows);
                continue;
            }

            fprintf(fres, "%s \n", buff);
        }
    }
}

int convert_mb_to_num_of_rows(int dataInMb) {
    return (dataInMb * MB_TO_KB) / sqrt(3*dataInMb);
};

int print_rand_numbers_into_file(FILE *f, int num_of_rows) {
    int i, j;
    for (i = 0; i < num_of_rows;i++) {
        for (j = 0; j < num_of_rows - 1; j++) {
            fprintf(f, "%d ", rand()%100);
        }
        fprintf(f, "%d", rand()%100);
        fprintf(f, "\n");
    }
    printf("INFO: Data successfully generated\n");

    return 0;
}

int generate_data() {
    int dataInMb;
    FILE *f;

    f = get_fd(MATRIX_PATH,"w+b");

    printf("Enter amount of data in MB\n");
    scanf("%d", &dataInMb);

    int res = convert_mb_to_num_of_rows(dataInMb);
    print_rand_numbers_into_file(f, res);

    fclose(f);

    return res;
}

// socket create and verification
int create_and_verify_socket() {
    int sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd == -1) {
        printf("ERROR: Socket creation failed...\n");
        exit(0);
    }
    printf("INFO: Socket successfully created..\n");
    return sock_fd;
}

// assign IP, PORT
int configure_serv_addr(struct sockaddr_in * serv_addr, int sockfd) {
    bzero(serv_addr, sizeof(*serv_addr));

    serv_addr->sin_family = AF_INET;
    serv_addr->sin_addr.s_addr = htonl(INADDR_ANY);
    serv_addr->sin_port = htons(PORT);

    // Binding newly created socket to given IP and verification
    if ((bind(sockfd, (SA*)serv_addr, sizeof(*serv_addr))) != 0) {
        printf("ERROR: Socket bind failed...\n");
        exit(0);
    }
    else
        printf("INFO: Socket successfully binded..\n");

    return sockfd;
}

// Now server is ready to listen and verification
int socket_start_listen(int sockfd) {
    if ((listen(sockfd, 5)) != 0) {
        printf("ERROR: Listen failed...\n");
        exit(0);
    }
    else
        printf("INFO: Server listening..\n");

    return 0;
}

// Accept the data packet from client and verification
int get_server_accept(int sockfd, struct sockaddr_in * cli) {
    socklen_t len = sizeof(*cli);
    int connfd = accept(sockfd, (SA*)cli, &len);

    if (connfd < 0) {
        printf("ERROR: Server accept failed...\n");
        exit(0);
    }
    else
        printf("INFO: Server accept the client...\n");
    return connfd;
}

// Driver function
int main()
{
    int num_of_rows = generate_data();
    int sockfd, connfd;
    struct sockaddr_in serv_addr, cli;

    if (num_of_rows == -1) {
        printf("ERROR: Trouble with data generation");
    }

    sockfd = create_and_verify_socket();
    configure_serv_addr(&serv_addr, sockfd);
    socket_start_listen(sockfd);

    connfd = get_server_accept(sockfd, &cli);

    //main func
    func(connfd, num_of_rows);

    // After chatting close the socket
    close(sockfd);
}

